// V2.8.2: 4x4 spatially sampled frame-luma statistics for sensor AE.
// The pixel output remains a one-clock pass-through stage. Statistics are
// computed from the fixed/raw RGB stream BEFORE display AWB/HE; PV detection
// also continues to consume pixel_in directly, so AWB cannot move CCL thresholds.
//
// For the fixed 1280x720 mode, one sample is taken at x%4==0 && y%4==0:
// 320*180 = 57,600 samples. The 24-bit accumulator is sufficient because
// 57,600*255 = 14,688,000. avg ~= sum*146 / 2^23 (shift/add only).
// Changing resolution requires rechecking FRAME_PIXELS and the reciprocal.
module auto_exposure #(
  parameter integer IMG_WIDTH=1280, IMG_HEIGHT=720,
  parameter integer TARGET_LOW=120, TARGET_HIGH=136,
  parameter integer GAIN_MIN=224, GAIN_MAX=288, GAIN_STEP=4
)(
  input wire clk,
  input wire rst_n,
  input wire enable,
  input wire stats_enable,       // 0 during CAM ERR: do not learn repeated DDR frames
  input wire frame_start,
  input wire line_end,
  input wire de,
  input wire [23:0] pixel_in,
  output reg [23:0] pixel_out,
  output reg [7:0] frame_stat_y,
  output reg frame_stat_toggle
);
  localparam integer FRAME_PIXELS = IMG_WIDTH * IMG_HEIGHT;

  reg [23:0] luma_sum;
  reg [19:0] pixel_count;       // 921,600 active pixels fits in 20 bits
  reg [10:0] x_count;
  reg [9:0]  y_count;

  // BT.601 Y ~= (77R + 150G + 29B) >> 8. Shift/add keeps DSP usage at zero.
  wire [7:0] r = pixel_in[23:16];
  wire [7:0] g = pixel_in[15:8];
  wire [7:0] b = pixel_in[7:0];
  wire [16:0] weighted =
      ({9'd0,r} << 6) + ({9'd0,r} << 3) + ({9'd0,r} << 2) + r
    + ({9'd0,g} << 7) + ({9'd0,g} << 4) + ({9'd0,g} << 2) + ({9'd0,g} << 1)
    + ({9'd0,b} << 4) + ({9'd0,b} << 3) + ({9'd0,b} << 2) + b;
  wire [7:0] y = weighted[15:8];

  wire sample_pixel = de && (x_count[1:0] == 2'b00) &&
                           (y_count[1:0] == 2'b00);
  // 146 = 128 + 16 + 2. 32-bit intermediate is large enough for the
  // maximum 4x4-sampled sum multiplied by 146.
  wire [31:0] avg_mult = ({8'd0,luma_sum} << 7) +
                         ({8'd0,luma_sum} << 4) +
                         ({8'd0,luma_sum} << 1);
  wire [8:0] avg_4x4 = avg_mult[31:23];

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pixel_out <= 24'd0;
      luma_sum <= 24'd0;
      pixel_count <= 20'd0;
      x_count <= 11'd0;
      y_count <= 10'd0;
      frame_stat_y <= 8'd0;
      frame_stat_toggle <= 1'b0;
    end else begin
      // Preserve the established one-stage video timing independent of AE.
      pixel_out <= de ? pixel_in : 24'd0;

      if (!stats_enable) begin
        // Do not let a frozen/repeated DDR frame keep steering sensor AE.
        luma_sum <= 24'd0;
        pixel_count <= 20'd0;
        x_count <= 11'd0;
        y_count <= 10'd0;
      end else if (frame_start) begin
        // Publish the PREVIOUS frame only when its active-pixel count is sane.
        if ((IMG_WIDTH == 1280) && (IMG_HEIGHT == 720) &&
            (pixel_count >= FRAME_PIXELS - 16) &&
            (pixel_count <= FRAME_PIXELS + 16)) begin
          frame_stat_y <= (avg_4x4 > 9'd255) ? 8'hff : avg_4x4[7:0];
          frame_stat_toggle <= ~frame_stat_toggle;
        end
        // SOF is normally on pixel (0,0). If DE is asserted on this cycle,
        // include that first sample and leave x_count at the next x position.
        luma_sum <= de ? {16'd0,y} : 24'd0;
        pixel_count <= de ? 20'd1 : 20'd0;
        x_count <= de ? 11'd1 : 11'd0;
        y_count <= 10'd0;
      end else begin
        if (de) begin
          if (sample_pixel)
            luma_sum <= luma_sum + {16'd0,y};
          if (pixel_count != 20'hfffff)
            pixel_count <= pixel_count + 1'b1;
          if (x_count != 11'h7ff)
            x_count <= x_count + 1'b1;
        end
        // EOL resets horizontal sample phase and advances the row index.
        // If EOL and DE coincide on the last pixel, its sample/count above
        // still happens; these assignments only reset the coordinates.
        if (line_end) begin
          x_count <= 11'd0;
          if (y_count != 10'h3ff)
            y_count <= y_count + 1'b1;
        end
      end
    end
  end
endmodule
