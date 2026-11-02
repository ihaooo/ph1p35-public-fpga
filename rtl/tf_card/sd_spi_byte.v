// Portable synthesizable SPI mode-0 byte master. clk is the APB/system clock.
// SPI frequency = clk/(2*divider); divider >= 1.
module sd_spi_byte (
  input wire clk, rst_n,
  input wire start,
  input wire [15:0] divider,
  input wire [7:0] tx_data,
  output reg [7:0] rx_data,
  output reg busy,
  output reg done,
  output reg sclk,
  output reg mosi,
  input wire miso
);
  reg [15:0] phase_cnt;
  reg [2:0] bit_idx;
  reg [7:0] tx_shift;
  reg [7:0] rx_shift;
  wire [15:0] div_valid=(divider==0)?16'd1:divider;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_data<=0; busy<=0; done<=0; sclk<=0; mosi<=1;
      phase_cnt<=0; bit_idx<=0; tx_shift<=0; rx_shift<=0;
    end else begin
      done<=0;
      if (!busy) begin
        sclk<=0;
        if (start) begin
          busy<=1; phase_cnt<=0; bit_idx<=0;
          tx_shift<=tx_data; rx_shift<=0; mosi<=tx_data[7];
        end
      end else if (phase_cnt == div_valid-1'b1) begin
        phase_cnt<=0;
        if (!sclk) begin
          sclk<=1;
          rx_shift<={rx_shift[6:0],miso};
        end else begin
          sclk<=0;
          if (bit_idx==3'd7) begin
            busy<=0; done<=1; rx_data<=rx_shift; mosi<=1;
          end else begin
            bit_idx<=bit_idx+1'b1;
            tx_shift<={tx_shift[6:0],1'b1};
            mosi<=tx_shift[6];
          end
        end
      end else begin
        phase_cnt<=phase_cnt+1'b1;
      end
    end
  end
endmodule
