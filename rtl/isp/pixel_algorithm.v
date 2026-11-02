// Streaming pixel algorithms in the HDMI pixel clock domain.
// mode 0: passthrough, mode 1: binary, mode 2: gray, mode 3: Sobel edge,
// mode 4: cartoon (color quantization with Sobel edge overlay).
// mode 5: vintage sepia film RGB grade, low-area P4 reuse of existing RGB register.
module pixel_algorithm #(
    parameter integer IMG_WIDTH = 1280,
    parameter integer IMG_HEIGHT = 720,
    parameter integer BINARY_TH = 8'd96,
    parameter integer EDGE_TH = 11'd32,
    // 0=classic binary Sobel, 1=low-light-friendly colored edges + gray scene.
    parameter integer EDGE_VIEW_STYLE = 1,
    parameter integer EDGE_DARK_TH = 11'd40,
    parameter integer EDGE_DIM_TH = 11'd56,
    // Only Edge MODE 3 uses a causal strong/weak contour gate.
    // Strong Sobel samples must have another strong sample to their left,
    // directly above, or diagonally above-left; isolated dots are rejected.
    parameter integer EDGE_LINK_ENABLE = 1,
    parameter integer EDGE_STRONG_DELTA = 40,
    // Keep the cartoon mask threshold unchanged from v1.4.
    parameter integer CARTOON_EDGE_TH = 11'd80,
    parameter integer ADAPTIVE_BINARY = 1,
    parameter integer BINARY_BIAS = 8
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [2:0] mode,
    // Previous-frame mean luma from the existing sensor AE statistics.
    // Used only to choose a Sobel display threshold, not to change exposure.
    input  wire [7:0] scene_luma,
    input  wire       frame_start,
    input  wire       line_end,
    input  wire       de,
    input  wire [23:0] pixel_in,
    output reg  [23:0] pixel_out
);
    reg [31:0] binary_luma_sum;
    reg [21:0] binary_pixel_count;
    reg [7:0]  binary_threshold;

    // P0: RGB-to-luma is registered, so its adder tree cannot reach Sobel.
    reg [7:0]  gray_reg;
    reg [23:0] pixel_in_reg;
    reg        de_reg;
    reg        frame_start_reg;
    reg        line_end_reg;
    reg [2:0]  mode_reg;

    localparam [7:0] BINARY_TH_MIN = 8'd24;
    localparam [7:0] BINARY_TH_MAX = 8'd224;

    // BT.601 full-range luma: Y=(77R+150G+29B)>>8.  The coefficients
    // are decomposed into shifts, so this remains multiplier/DSP-free.
    function [7:0] rgb_to_y;
        input [23:0] rgb;
        reg [16:0] y_r;
        reg [16:0] y_g;
        reg [16:0] y_b;
        reg [16:0] y_sum;
        begin
            y_r   = ({9'd0,rgb[23:16]} << 6) +
                    ({9'd0,rgb[23:16]} << 3) +
                    ({9'd0,rgb[23:16]} << 2) + rgb[23:16];
            y_g   = ({9'd0,rgb[15:8]}  << 7) +
                    ({9'd0,rgb[15:8]}  << 4) +
                    ({9'd0,rgb[15:8]}  << 2) +
                    ({9'd0,rgb[15:8]}  << 1);
            y_b   = ({9'd0,rgb[7:0]}   << 4) +
                    ({9'd0,rgb[7:0]}   << 3) +
                    ({9'd0,rgb[7:0]}   << 2) + rgb[7:0];
            y_sum = y_r + y_g + y_b;
            rgb_to_y = y_sum[15:8];
        end
    endfunction

    wire [7:0] gray = rgb_to_y(pixel_in);
    // 1280x720 has 921600 active pixels.  146/2^27 is its reciprocal to
    // better than 0.2%; the shift/add form avoids a run-time divider.
    wire [39:0] binary_avg_product =
                         ({8'd0,binary_luma_sum} << 7) +
                         ({8'd0,binary_luma_sum} << 4) +
                         ({8'd0,binary_luma_sum} << 1);
    wire [8:0] binary_avg_calc = binary_avg_product[35:27];

    function [7:0] make_binary_threshold;
        input [8:0] average;
        reg [9:0] candidate;
        begin
            candidate = average + BINARY_BIAS;
            if (candidate < BINARY_TH_MIN)
                make_binary_threshold = BINARY_TH_MIN;
            else if (candidate > BINARY_TH_MAX)
                make_binary_threshold = BINARY_TH_MAX;
            else
                make_binary_threshold = candidate[7:0];
        end
    endfunction

    wire [7:0] binary_threshold_target =
                         make_binary_threshold(binary_avg_calc);
    wire [7:0] binary_threshold_used = ADAPTIVE_BINARY ?
                                        binary_threshold : BINARY_TH;

    // ===============================================================
    // V2.1 timing repair: strictly pipelined 3x3 Gaussian -> Sobel
    // ===============================================================
    // V2.0 used a full 9-input bubble-sort median (36 sequential
    // compare/swap decisions) on the pixel clock critical path. It also
    // wrote that median result into the raw-line history, extending the
    // dependency chain through the image state. The timing report showed
    // 45 logic levels and -23.698 ns from pixel_algorithm into the Logo.
    //
    // V2.1 removes the sorting network but PRESERVES edge denoising:
    //   P0 RGB -> Y (existing register)
    //   P1 raw 3x3 -> binomial Gaussian /16 (register)
    //   P2 filtered 3x3 -> four Sobel half sums (register)
    //   P3 Gx,Gy differences (register)
    //   P4 abs(Gx)+abs(Gy) (register)
    //   P5 mode/threshold/RGB output (register)
    // P0..P5 form SIX clocked stages, including passthrough modes.
    // Control strobes, mode, raw RGB and gray travel through the SAME
    // six stages. Video timing is correspondingly delayed in
    // vision_pipeline.v by six clocks; never change one without the other.
    // No multiplier, division, large combinational median or frame buffer.

    // Raw luma line history. IMPORTANT: write RAW gray, never blur result.
    (* ram_style = "block" *) reg [7:0] raw_line1 [0:IMG_WIDTH-1];
    (* ram_style = "block" *) reg [7:0] raw_line2 [0:IMG_WIDTH-1];
    reg [10:0] raw_x, raw_y;
    reg [7:0] rt2, rt1, rm2, rm1, rb2, rb1;
    wire [7:0] rt0 = raw_line2[raw_x];
    wire [7:0] rm0 = raw_line1[raw_x];
    wire [7:0] rb0 = gray_reg;

    // Gaussian weights:
    //    1 2 1
    //    2 4 2  / 16
    //    1 2 1
    // Three 10-bit horizontal sums, one 12-bit vertical sum. Synthesis
    // sees only add/shift, no 8-bit compare/swap chain.
    wire [9:0] raw_ht = {2'b00,rt2} + {1'b0,rt1,1'b0} + {2'b00,rt0};
    wire [9:0] raw_hm = {2'b00,rm2} + {1'b0,rm1,1'b0} + {2'b00,rm0};
    wire [9:0] raw_hb = {2'b00,rb2} + {1'b0,rb1,1'b0} + {2'b00,rb0};
    wire [12:0] gauss_sum = {3'b000,raw_ht} + {2'b00,raw_hm,1'b0} +
                            {3'b000,raw_hb} + 13'd8;
    // Rounded /16; result fits 0..255.
    reg [7:0] smooth_s1;
    reg [23:0] rgb_s1;
    reg [7:0] gray_s1;
    reg [2:0] mode_s1;
    reg de_s1, sof_s1, eol_s1;

    // Filtered line history is separate from raw history. This is what
    // truly makes the Gaussian a prefilter rather than an unrelated mask.
    (* ram_style = "block" *) reg [7:0] smooth_line1 [0:IMG_WIDTH-1];
    (* ram_style = "block" *) reg [7:0] smooth_line2 [0:IMG_WIDTH-1];
    reg [10:0] smooth_x, smooth_y;
    reg [7:0] st2, st1, sm2, sm1, sb2, sb1;
    wire [7:0] st0 = smooth_line2[smooth_x];
    wire [7:0] sm0 = smooth_line1[smooth_x];
    wire [7:0] sb0 = smooth_s1;

    // Sobel is split into four NON-SIGNED 10-bit half-sums. This stage
    // has just two 10-bit adders in series instead of a full Gx/Gy tree.
    wire [9:0] left_x   = {2'b00,st2} + {1'b0,sm2,1'b0} + {2'b00,sb2};
    wire [9:0] right_x  = {2'b00,st0} + {1'b0,sm0,1'b0} + {2'b00,sb0};
    wire [9:0] top_y    = {2'b00,st2} + {1'b0,st1,1'b0} + {2'b00,st0};
    wire [9:0] bottom_y = {2'b00,sb2} + {1'b0,sb1,1'b0} + {2'b00,sb0};
    reg [9:0] left_s2, right_s2, top_s2, bottom_s2;
    reg [23:0] rgb_s2;
    reg [7:0] gray_s2;
    reg [2:0] mode_s2;
    reg de_s2, valid_s2, sof_s2, eol_s2;

    reg signed [11:0] gx_s3, gy_s3;
    reg [23:0] rgb_s3;
    reg [7:0] gray_s3;
    reg [2:0] mode_s3;
    reg de_s3, valid_s3, sof_s3, eol_s3;

    wire [11:0] mag_x = gx_s3[11] ? -gx_s3 : gx_s3;
    wire [11:0] mag_y = gy_s3[11] ? -gy_s3 : gy_s3;
    // V2.6.4.1 AREA FIX (MODE 5): warm sepia film using the existing
    // registered luma. Unlike v2.6.4, do NOT build three (3*C+Y)/4
    // mixers and do NOT add 30 extra per-pixel flops.
    // Compute in P4, conditionally write into the EXISTING rgb_s4 flop.
    // P5 output mux and video timing remain exactly six clock cycles.
    // R = saturate(Y + 18); G = saturate(Y + 8);
    // B = max(Y - 10, 0). All operations are fixed-constant 8-bit add/sub.
    // The revised look is sepia / warm-monochrome rather than the previous
    // subtly desaturated RGB look; it is an intentional area/quality tradeoff.
    wire [8:0] film_r_add = {1'b0, gray_s3} + 9'd18;
    wire [8:0] film_g_add = {1'b0, gray_s3} + 9'd8;
    wire [7:0] film_r_sep = film_r_add[8] ? 8'hff : film_r_add[7:0];
    wire [7:0] film_g_sep = film_g_add[8] ? 8'hff : film_g_add[7:0];
    wire [7:0] film_b_sep = (gray_s3 < 8'd10) ? 8'd0 :
                            (gray_s3 - 8'd10);
    wire [23:0] film_sepia_p4 = {film_r_sep, film_g_sep, film_b_sep};

    reg [12:0] magnitude_s4;
    reg [23:0] rgb_s4;
    reg [7:0] gray_s4;
    reg [2:0] mode_s4;
    reg de_s4, valid_s4, sof_s4, eol_s4;

    // ===============================================================
    // V2.2: clean contours instead of isolated CMOS/high-gain speckles.
    // ===============================================================
    // The official lab_ex2_edge_SC520 reference performs Sobel with one
    // threshold, but cannot suppress isolated white dots. On the real
    // board the old dark threshold (40) showed nearly every noisy pixel.
    // We keep the *same six-cycle video pipeline*, add no extra pixel
    // latency, and only change the MODE 3 Sobel output decision.
    //
    // EDGE_LOW: possible contour. EDGE_HIGH: reliable contour.
    // For each pixel, scan a causal neighborhood of strong samples:
    //      up-left    up
    //          left  current
    // A pixel is shown if it is strong and touches a previous strong
    // point, or if it is weak and has strong left AND above neighbors.
    // This is NOT full Canny hysteresis nor full 3x3 erosion/opening.
    // Its advantage is: no frame memory, no line latency, no extra
    // RGB/DE/SOF/HSYNC/VSYNC alignment changes, and low timing cost.
    //
    // The history line stores raw strong-candidate bits, not the final
    // output, so the mask cannot feed back and grow indefinitely.
    wire [10:0] edge_low_th =
        (scene_luma < 8'd64)  ? EDGE_DARK_TH :
        (scene_luma < 8'd112) ? EDGE_DIM_TH : EDGE_TH;
    wire [11:0] edge_high_th = {1'b0, edge_low_th} + EDGE_STRONG_DELTA;
    wire edge_low_now  = valid_s4 && (magnitude_s4 >= {2'b0,edge_low_th});
    wire edge_high_now = valid_s4 && (magnitude_s4 >= edge_high_th);

    // A single-bit previous-line memory: IMG_WIDTH bits (1280 at 720p).
    // Memories are intentionally not reset: first 4 lines are masked by
    // valid_s4, and all rows are overwritten naturally each frame.
    (* ram_style = "distributed" *) reg edge_high_row [0:IMG_WIDTH-1];
    reg [10:0] edge_col;
    reg edge_left_hi, edge_up_left_hi;
    wire [10:0] edge_col_now = sof_s4 ? 11'd0 : edge_col;
    wire edge_up_hi = edge_high_row[edge_col_now];
    wire edge_neighbors = edge_left_hi | edge_up_hi | edge_up_left_hi;
    wire edge_linked = (edge_high_now && edge_neighbors) ||
                       (edge_low_now && edge_left_hi && edge_up_hi);
    wire edge_hit = EDGE_LINK_ENABLE ? edge_linked : edge_low_now;

    // Keep faint context but reduce the intensity of the gray background.
    wire [7:0] edge_bg = (gray_s4 >> 2) + 8'd12;
    wire [23:0] enhanced_edge = edge_hit ? 24'h60ffe0 :
                                         {edge_bg,edge_bg,edge_bg};
    wire [23:0] bw_edge = edge_hit ? 24'hffffff : 24'h000000;
    wire [23:0] edge_pixel = EDGE_VIEW_STYLE == 0 ? bw_edge : enhanced_edge;
    wire [23:0] cartoon_quantized = {rgb_s4[23:20],4'b0,
                                     rgb_s4[15:12],4'b0,
                                     rgb_s4[7:4],4'b0};
    wire [23:0] cartoon_pixel =
                 (valid_s4 && magnitude_s4 >= CARTOON_EDGE_TH) ?
                              24'h282828 : cartoon_quantized;

    // Binary threshold input was defined above; no duplicate wiring.

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gray_reg <= 8'd0;
            pixel_in_reg <= 24'd0;
            de_reg <= 1'b0;
            frame_start_reg <= 1'b0;
            line_end_reg <= 1'b0;
            mode_reg <= 3'd0;

            raw_x <= 0; raw_y <= 0;
            rt2<=0;rt1<=0;rm2<=0;rm1<=0;rb2<=0;rb1<=0;
            smooth_s1<=0;rgb_s1<=0;gray_s1<=0;mode_s1<=0;
            de_s1<=0;sof_s1<=0;eol_s1<=0;
            smooth_x<=0;smooth_y<=0;
            st2<=0;st1<=0;sm2<=0;sm1<=0;sb2<=0;sb1<=0;
            left_s2<=0;right_s2<=0;top_s2<=0;bottom_s2<=0;
            rgb_s2<=0;gray_s2<=0;mode_s2<=0;de_s2<=0;valid_s2<=0;sof_s2<=0;eol_s2<=0;
            gx_s3<=0;gy_s3<=0;
            rgb_s3<=0;gray_s3<=0;mode_s3<=0;de_s3<=0;valid_s3<=0;sof_s3<=0;eol_s3<=0;
            magnitude_s4<=0;
            rgb_s4<=0;gray_s4<=0;mode_s4<=0;de_s4<=0;valid_s4<=0;sof_s4<=0;eol_s4<=0;
            edge_col<=0;edge_left_hi<=0;edge_up_left_hi<=0;
            pixel_out<=0;
            binary_luma_sum<=0;
            binary_pixel_count<=0;
            binary_threshold<=BINARY_TH;
        end else begin
            // P0: RGB brightness and the frame metadata.
            gray_reg        <= gray;
            pixel_in_reg    <= pixel_in;
            de_reg          <= de;
            frame_start_reg <= frame_start;
            line_end_reg    <= line_end;
            mode_reg        <= mode;

            // P1: blur output, plus pixel and qualifiers through same stage.
            smooth_s1 <= gauss_sum[11:4];
            rgb_s1<=pixel_in_reg;
            gray_s1<=gray_reg;
            mode_s1<=mode_reg;
            de_s1<=de_reg;
            sof_s1<=frame_start_reg;
            eol_s1<=line_end_reg;

            // The input raster controls raw-line history, NOT Sobel logic.
            if (frame_start_reg) begin
                raw_x<=0;raw_y<=0;
                rt2<=0;rt1<=0;rm2<=0;rm1<=0;rb2<=0;rb1<=0;
                binary_luma_sum <= de_reg ? {24'd0,gray_reg} : 32'd0;
                binary_pixel_count <= de_reg ? 22'd1 : 22'd0;
                if (binary_pixel_count != 0) begin
                    if (!ADAPTIVE_BINARY)
                        binary_threshold<=BINARY_TH;
                    else if (binary_threshold < binary_threshold_target) begin
                        if ((binary_threshold_target - binary_threshold)>8)
                            binary_threshold<=binary_threshold+8;
                        else binary_threshold<=binary_threshold_target;
                    end else if (binary_threshold > binary_threshold_target) begin
                        if ((binary_threshold - binary_threshold_target)>8)
                            binary_threshold<=binary_threshold-8;
                        else binary_threshold<=binary_threshold_target;
                    end
                end
            end else if (de_reg) begin
                binary_luma_sum <= binary_luma_sum + gray_reg;
                if (binary_pixel_count != 22'h3fffff)
                    binary_pixel_count<=binary_pixel_count+1'b1;
                raw_line2[raw_x] <= rm0;
                raw_line1[raw_x] <= gray_reg;
                rt2<=rt1;rt1<=rt0;
                rm2<=rm1;rm1<=rm0;
                rb2<=rb1;rb1<=rb0;
                if (line_end_reg) begin
                    raw_x<=0;
                    if (raw_y==IMG_HEIGHT-1) raw_y<=0;
                    else raw_y<=raw_y+1'b1;
                    rt2<=0;rt1<=0;rm2<=0;rm1<=0;rb2<=0;rb1<=0;
                end else if (raw_x==IMG_WIDTH-1) raw_x<=0;
                else raw_x<=raw_x+1'b1;
            end

            // P2: filtered-line history + parallel registered Sobel halves.
            left_s2<=left_x;
            right_s2<=right_x;
            top_s2<=top_y;
            bottom_s2<=bottom_y;
            rgb_s2<=rgb_s1;
            gray_s2<=gray_s1;
            mode_s2<=mode_s1;
            de_s2<=de_s1;
            valid_s2<=de_s1 && (smooth_x>=11'd4) && (smooth_y>=11'd4);
            sof_s2<=sof_s1; eol_s2<=eol_s1;
            if (sof_s1) begin
                smooth_x<=0;smooth_y<=0;
                st2<=0;st1<=0;sm2<=0;sm1<=0;sb2<=0;sb1<=0;
            end else if (de_s1) begin
                smooth_line2[smooth_x] <= sm0;
                smooth_line1[smooth_x] <= smooth_s1;
                st2<=st1;st1<=st0;
                sm2<=sm1;sm1<=sm0;
                sb2<=sb1;sb1<=sb0;
                if (eol_s1) begin
                    smooth_x<=0;
                    if (smooth_y==IMG_HEIGHT-1) smooth_y<=0;
                    else smooth_y<=smooth_y+1'b1;
                    st2<=0;st1<=0;sm2<=0;sm1<=0;sb2<=0;sb1<=0;
                end else if (smooth_x==IMG_WIDTH-1) smooth_x<=0;
                else smooth_x<=smooth_x+1'b1;
            end

            // P3: two subtractions, independent of the raster buffers.
            gx_s3 <= $signed({2'b0,right_s2}) - $signed({2'b0,left_s2});
            gy_s3 <= $signed({2'b0,bottom_s2}) - $signed({2'b0,top_s2});
            rgb_s3<=rgb_s2;gray_s3<=gray_s2;mode_s3<=mode_s2;
            de_s3<=de_s2;valid_s3<=valid_s2;
            sof_s3<=sof_s2;eol_s3<=eol_s2;

            // P4: absolute values then one bounded 13-bit adder.
            magnitude_s4 <= {1'b0,mag_x} + {1'b0,mag_y};
            // Preserve a single RGB register set: no separate film_s4.
            // mode_s3 is pipeline-aligned with rgb_s3 and gray_s3.
            rgb_s4 <= (mode_s3 == 3'd5) ? film_sepia_p4 : rgb_s3;
            gray_s4<=gray_s3;mode_s4<=mode_s3;
            de_s4<=de_s3;valid_s4<=valid_s3;
            sof_s4<=sof_s3;eol_s4<=eol_s3;

            // Strong-edge history advances ONLY on active image pixels.
            // During horizontal blanking, row bits and neighbor taps hold.
            // Frame SOF applies to column 0 even when SOF and DE coincide.
            if (sof_s4) begin
                edge_col<=11'd0;
                edge_left_hi<=1'b0;
                edge_up_left_hi<=1'b0;
            end
            if (de_s4) begin
                edge_high_row[edge_col_now] <= edge_high_now;
                edge_left_hi <= edge_high_now;
                edge_up_left_hi <= edge_up_hi;
                if (eol_s4 || edge_col_now == IMG_WIDTH-1) begin
                    edge_col<=11'd0;
                    edge_left_hi<=1'b0;
                    edge_up_left_hi<=1'b0;
                end else edge_col<=edge_col_now+1'b1;
            end else if (eol_s4) begin
                edge_col<=11'd0;
                edge_left_hi<=1'b0;
                edge_up_left_hi<=1'b0;
            end

            // P5: display selection. ALL modes, including raw passthrough,
            // are sampled at the same cycle (no mode-specific skew).
            if (!de_s4) pixel_out<=24'd0;
            else case (mode_s4)
                3'd1: pixel_out <= (gray_s4>=binary_threshold_used) ?
                                   24'hffffff:24'h000000;
                3'd2: pixel_out <= {gray_s4,gray_s4,gray_s4};
                3'd3: pixel_out <= edge_pixel;
                3'd4: pixel_out <= cartoon_pixel;
                3'd5: pixel_out <= rgb_s4;  // sepia already in P4 RGB
                default: pixel_out <= rgb_s4;
            endcase
        end
    end
endmodule
