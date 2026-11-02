// APB3-like slave to transfer SD-card SPI bytes (mode 0).
// Register offsets: 0x00 CTRL (bit0=cs_n); 0x04 DIV; 0x08 TX/start;
// 0x0C STATUS (bit0=busy, bit1=done, bit2=ignored-start); 0x10 RX.
// APB address decode is to be done by MCU platform, paddr[4:2] is used here.
module sd_spi_apb (
  input wire pclk, presetn,
  input wire [19:0] paddr,
  input wire psel, penable, pwrite,
  input wire [31:0] pwdata,
  output reg [31:0] prdata,
  output wire pready, pslverr,
  output reg sd_cs_n,
  output wire sd_sclk, sd_mosi,
  input wire sd_miso
);
  reg [15:0] clk_div;
  reg [7:0] tx_data;
  reg start;
  reg ignored_start;
  reg done_latched;
  wire busy,done;
  wire [7:0] rx_data;
  assign pready=1'b1;
  assign pslverr=1'b0;
  sd_spi_byte u_spi(.clk(pclk),.rst_n(presetn),.start(start),
       .divider(clk_div),.tx_data(tx_data),.rx_data(rx_data),
       .busy(busy),.done(done),.sclk(sd_sclk),.mosi(sd_mosi),.miso(sd_miso));
  always @(*) begin
    case(paddr[4:2])
      3'd0: prdata={31'd0,sd_cs_n};
      3'd1: prdata={16'd0,clk_div};
      3'd2: prdata={24'd0,tx_data};
      3'd3: prdata={29'd0,ignored_start,done_latched,busy};
      3'd4: prdata={24'd0,rx_data};
      default: prdata=32'd0;
    endcase
  end
  always @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      sd_cs_n<=1; clk_div<=16'd100; tx_data<=8'hff;
      start<=0; ignored_start<=0; done_latched<=0;
    end else begin
      start<=0;
      if(done) done_latched<=1;
      if(psel && penable && pwrite) begin
        case(paddr[4:2])
          3'd0: sd_cs_n<=pwdata[0];
          3'd1: clk_div <= (pwdata[15:0]==0) ? 16'd1 : pwdata[15:0];
          3'd2: if(!busy && !start) begin
                    tx_data<=pwdata[7:0]; start<=1;
                    done_latched<=0; ignored_start<=0;
                end else ignored_start<=1;
          3'd3: if(pwdata[2]) ignored_start<=0;
          default: ;
        endcase
      end
    end
  end
endmodule
