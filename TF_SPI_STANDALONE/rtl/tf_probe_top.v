// Independent TF card CMD0 hardware probe for HX1P35A.
// LED1 lit => CMD0 returned 0x01. LED2 lit => unexpected response or timeout.
// KEY1 (active-low) resets. LED3 heartbeat; LED4 active while probing.
// Does not run MCU, FAT32 or inference: explicitly a wiring/protocol smoke test.
module tf_probe_top (
  input wire I_sys_clk, I_rst_n,
  output wire SD_CLK, SD_CMD, SD_DAT3,
  input wire SD_DAT0,
  output wire LED1, LED2, LED3, LED4
);
  localparam WAIT_POWER=4'd0, START_DUMMY=4'd1, WAIT_DUMMY=4'd2,
             START_CMD=4'd3, WAIT_CMD=4'd4,
             START_RESP=4'd5, WAIT_RESP=4'd6, PASS=4'd7, FAIL=4'd8;
  reg [3:0] state;
  reg [17:0] wait_cnt;
  reg [3:0] byte_idx;
  reg [4:0] attempts;
  reg [7:0] data_tx;
  reg spi_go;
  reg cs_n;
  wire busy,done;
  wire [7:0] rx;
  reg [25:0] heartbeat;
  sd_spi_byte u_spi(.clk(I_sys_clk),.rst_n(I_rst_n),
    .start(spi_go),.divider(16'd100),.tx_data(data_tx),
    .rx_data(rx),.busy(busy),.done(done),
    .sclk(SD_CLK),.mosi(SD_CMD),.miso(SD_DAT0));
  assign SD_DAT3=cs_n;
  assign LED1=(state==PASS);
  assign LED2=(state==FAIL);
  assign LED3=heartbeat[25];
  assign LED4=(state!=PASS && state!=FAIL);
  always @(posedge I_sys_clk or negedge I_rst_n) begin
    if(!I_rst_n) heartbeat<=0;
    else heartbeat<=heartbeat+1'b1;
  end
  always @(posedge I_sys_clk or negedge I_rst_n) begin
    if(!I_rst_n) begin
      state<=WAIT_POWER; wait_cnt<=0; byte_idx<=0; attempts<=0;
      data_tx<=8'hff; spi_go<=0; cs_n<=1;
    end else begin
      spi_go<=0;
      case(state)
        WAIT_POWER: begin
          if(wait_cnt==18'd249999) begin
            wait_cnt<=0; byte_idx<=0; state<=START_DUMMY;
          end else wait_cnt<=wait_cnt+1'b1;
        end
        START_DUMMY: if(!busy) begin
          data_tx<=8'hff; spi_go<=1; state<=WAIT_DUMMY;
        end
        WAIT_DUMMY: if(done) begin
          if(byte_idx==4'd9) begin
            cs_n<=0; byte_idx<=0; state<=START_CMD;
          end else begin
            byte_idx<=byte_idx+1'b1; state<=START_DUMMY;
          end
        end
        START_CMD: if(!busy) begin
          case(byte_idx)
            0: data_tx<=8'h40; // CMD0
            1: data_tx<=8'h00;
            2: data_tx<=8'h00;
            3: data_tx<=8'h00;
            4: data_tx<=8'h00;
            default: data_tx<=8'h95; // valid CRC for CMD0
          endcase
          spi_go<=1; state<=WAIT_CMD;
        end
        WAIT_CMD: if(done) begin
          if(byte_idx==4'd5) begin attempts<=0;state<=START_RESP; end
          else begin byte_idx<=byte_idx+1'b1;state<=START_CMD;end
        end
        START_RESP: if(!busy) begin
          data_tx<=8'hff; spi_go<=1; state<=WAIT_RESP;
        end
        WAIT_RESP: if(done) begin
          if(rx==8'h01) begin cs_n<=1; state<=PASS; end
          else if(rx!=8'hff || attempts==5'd15) begin
            cs_n<=1;state<=FAIL;
          end else begin attempts<=attempts+1'b1;state<=START_RESP;end
        end
        PASS: state<=PASS;
        FAIL: state<=FAIL;
        default: state<=FAIL;
      endcase
    end
  end
endmodule
