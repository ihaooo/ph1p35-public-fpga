// Compact feature status overlay for board bring-up.
// The overlay is placed before the HDMI mixer so its pixel coordinates and
// timing are delayed together with the video stream.
module status_overlay #(
    parameter integer IMG_WIDTH  = 1280,
    parameter integer IMG_HEIGHT = 720,
    parameter integer SHOW_FRAME_COUNT = 0
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_start,
    input  wire        line_end,
    input  wire        de,
    input  wire [3:0]  feature_enable,
    input  wire [7:0]  frame_luma,
    input  wire [2:0]  algorithm_mode,
    input  wire [11:0] latency_cycles,
    input  wire [15:0] capture_frame_id,
    input  wire [15:0] display_frame_id,
    input  wire [11:0] frame_lag_frames,
    input  wire        frame_tag_valid,
    input  wire pv_enable,
    input  wire cam_fault,
    input  wire [7:0] cam_fault_count,
    input  wire pv_ae_hold, // 1: true sensor AE HOLD; 0: display AE ON/OFF
    input  wire pv_calibrated,
    input  wire pv_dirty,
    input  wire pv_motion,
    input  wire ccl_ready,
    input  wire ccl_overflow,
    input  wire ccl_overrun,
    input  wire [2:0] ccl_box_count,
    input  wire [1:0] ccl0_class,
    input  wire [1:0] ccl1_class,
    input  wire [1:0] ccl2_class,
    input  wire [1:0] ccl3_class,
    input  wire [23:0] pixel_in,
    output reg  [23:0] pixel_out
);
    localparam integer PANEL_W = 192;
    localparam integer PANEL_X = (IMG_WIDTH > PANEL_W + 16) ? IMG_WIDTH - PANEL_W - 8 : 0;
    localparam integer PANEL_Y = 18;
    localparam integer PANEL_H = 352;  // 11 rows: delete BOX and C0..C3; retain diagnostics
    localparam integer TEXT_X  = 14;
    localparam integer CELL_W  = 20;
    localparam integer CELL_H  = 32;

    reg [15:0] display_frame_count; // wraps after 65535 HDMI input frames
    // CCL readiness/camera error remain frame-coherent; detailed C0..C3
    // text is intentionally hidden, not disabled in the detector.
    reg ccl_ready_q;
    reg [7:0] cam_fault_count_q;
    reg [11:0] x;
    reg [11:0] y;
    wire in_panel = de && (x >= PANEL_X) && (x < PANEL_X + PANEL_W) &&
                    (y >= PANEL_Y) && (y < PANEL_Y + PANEL_H);
    wire [11:0] panel_x = x - PANEL_X;
    wire [11:0] panel_y = y - PANEL_Y;
    // Eight cells are required for the latency string: "LAT 005C".
    // All rows reserve the same state column so ON and OFF align vertically.
    wire text_area = in_panel && (panel_x >= TEXT_X) &&
                     (panel_x < TEXT_X + 8 * CELL_W);
    wire [3:0] row_index = (panel_y / CELL_H);
    wire [2:0] char_index = ((panel_x - TEXT_X) / CELL_W);
    wire [4:0] char_x = ((panel_x - TEXT_X) % CELL_W);
    wire [5:0] char_y = (panel_y % CELL_H);
    // Explicit ranges avoid general divide-by-3 combinational arithmetic.
    wire [2:0] glyph_row_index =
        (char_y < 5 || char_y >= 26) ? 3'd7 :
        (char_y < 8)  ? 3'd0 : (char_y < 11) ? 3'd1 :
        (char_y < 14) ? 3'd2 : (char_y < 17) ? 3'd3 :
        (char_y < 20) ? 3'd4 : (char_y < 23) ? 3'd5 : 3'd6;
    wire [2:0] glyph_col_index =
        (char_x < 3)  ? 3'd0 : (char_x < 6)  ? 3'd1 :
        (char_x < 9)  ? 3'd2 : (char_x < 12) ? 3'd3 :
        (char_x < 15) ? 3'd4 : (char_x < 18) ? 3'd5 : 3'd6;
    // Avoid an out-of-range dynamic bit-select on the fifth (latency) row.
    wire row_enabled = 1'b1; // status labels should remain readable even when OFF

    function [7:0] hex_char;
        input [3:0] value;
        begin
            if (value < 10) hex_char = 8'h30 + value;
            else hex_char = 8'h41 + value - 10;
        end
    endfunction

    // Compact HUD: 11 rows x 8 characters, one shared synchronous glyph ROM.
    // 0 PV CHECK, 1 MODE, 2 PV state,
    // 3 AE, 4 AWB, 5 HE, 6 LAT, 7 DIS, 8 LAG, 9 SYS, 10 ERR.
    // IMPORTANT: BOX/C0/C1/C2/C3 are removed from OSD ONLY.
    // Three AI objects and their bbox/classification logic remain unchanged.
    // Hide redundant debug counters; do not alter their upstream calculations.
    function [7:0] get_char;
        input [3:0] row;
        input [2:0] index;
        input enabled;
        input [3:0] features;
        input [11:0] latency;
        input [15:0] camera_id, output_id;
        input [11:0] lag_frames;
        input tag_ok;
        input [7:0] average_y;
        input [15:0] frame_num;
        input show_frame;
        input [2:0] mode;
        input pv_en, pv_ae_hold, pv_cal, pv_hit, pv_moving;
        input cam_missing;
        input [7:0] cam_errors;
        input ccl_is_ready, ccl_ovf, ccl_timeout;
            reg [7:0] state0, state1, state2, state3, state4;
        reg [7:0] sys0, sys1, sys2, sys3;
        begin
            // State labels: DEMO, WAIT, MOV, CLEAN, DIRTY and errors. No SETUP prompt.
            state0=8'h20; state1=8'h20; state2=8'h20; state3=8'h20; state4=8'h20;
            if (cam_missing) begin
                state0="W"; state1="A"; state2="I"; state3="T";
            end else if (!pv_en) begin state0="D"; state1="E"; state2="M"; state3="O"; end
            else if (ccl_ovf || ccl_timeout) begin
                state0="E"; state1="R"; state2="R";
            end else if (!pv_cal) begin
                // Not a request to calibrate: initial boot reference or
                // CCL synchronization is still in progress.
                state0="W"; state1="A"; state2="I"; state3="T";
            end else if (pv_moving) begin
                state0="M"; state1="O"; state2="V";
            end else if (pv_hit) begin
                state0="D"; state1="I"; state2="R"; state3="T"; state4="Y";
            end else begin
                state0="C"; state1="L"; state2="E"; state3="A"; state4="N";
            end
            if (cam_missing) begin
                sys0="E"; sys1="R"; sys2="R"; sys3=" ";
            end else if (ccl_ovf || ccl_timeout) begin
                sys0="E"; sys1="R"; sys2="R"; sys3=" ";
            end else if (!pv_en && tag_ok) begin
                sys0="O"; sys1="K"; sys2=" "; sys3=" ";
            end else if (!pv_cal || !ccl_is_ready || !tag_ok) begin
                sys0="W"; sys1="A"; sys2="I"; sys3="T";
            end else begin
                sys0="O"; sys1="K"; sys2=" "; sys3=" ";
            end
            get_char=" ";
            case (row)
              4'd0: case (index)
                0:get_char="P";1:get_char="V";3:get_char="C";
                4:get_char="H";5:get_char="E";6:get_char="C";7:get_char="K";
              endcase
              4'd1: case (index)
                0:get_char="M";1:get_char="O";2:get_char="D";3:get_char="E";
                6:get_char="0";7:get_char=8'h30+{5'b0,mode};
              endcase
              4'd2: case (index)
                0:get_char="P";1:get_char="V";
                3:get_char=state0;4:get_char=state1;5:get_char=state2;
                6:get_char=state3;7:get_char=state4;
              endcase
              4'd3: case (index)
                0:get_char="A";1:get_char="E";
                3:get_char=(pv_ae_hold && pv_en) ? "H" : "O";
                4:get_char=(pv_ae_hold && pv_en) ? "O" : (features[0] ? "N":"F");
                5:get_char=(pv_ae_hold && pv_en) ? "L" : (features[0] ? " ":"F");
                6:get_char=(pv_ae_hold && pv_en) ? "D" : " ";
              endcase
              4'd4: case (index)
                0:get_char="A";1:get_char="W";2:get_char="B";
                4:get_char="O";5:get_char=features[1]?"N":"F";
                6:get_char=features[1]?" ":"F";
              endcase
              4'd5: case (index)
                0:get_char="H";1:get_char="E";
                4:get_char="O";5:get_char=features[2]?"N":"F";
                6:get_char=features[2]?" ":"F";
              endcase
              4'd6: case (index)
                0:get_char="L";1:get_char="A";2:get_char="T";
                4:get_char="0";5:get_char=hex_char(latency[11:8]);
                6:get_char=hex_char(latency[7:4]);7:get_char=hex_char(latency[3:0]);
              endcase
              4'd7: case (index)
                0:get_char="D";1:get_char="I";2:get_char="S";
                4:get_char=tag_ok?hex_char(output_id[15:12]):"-";
                5:get_char=tag_ok?hex_char(output_id[11:8]):"-";
                6:get_char=tag_ok?hex_char(output_id[7:4]):"-";
                7:get_char=tag_ok?hex_char(output_id[3:0]):"-";
              endcase
              4'd8: case (index)
                0:get_char="L";1:get_char="A";2:get_char="G";
                4:get_char=tag_ok?hex_char(lag_frames[11:8]):"-";
                5:get_char=tag_ok?hex_char(lag_frames[7:4]):"-";
                6:get_char=tag_ok?hex_char(lag_frames[3:0]):"-";
                7:get_char="F";
              endcase
              4'd9: if (cam_missing) begin
                case (index)
                    0:get_char="C";1:get_char="A";2:get_char="M";
                    4:get_char="E";5:get_char="R";6:get_char="R";
                endcase
              end else begin
                case (index)
                    0:get_char="S";1:get_char="Y";2:get_char="S";
                    4:get_char=sys0;5:get_char=sys1;6:get_char=sys2;7:get_char=sys3;
                endcase
              end
              4'd10: case (index)
                0:get_char="E";1:get_char="R";2:get_char="R";
                4:get_char="0";5:get_char="0";
                6:get_char=hex_char(cam_errors[7:4]);
                7:get_char=hex_char(cam_errors[3:0]);
              endcase
            endcase
        end
    endfunction

    // 5x7 glyphs, scaled 3x in X/Y: 15x21 glyph inside a 20x32 row cell.
    // Pixel stages: S0 character/metadata capture, S1 synchronous ROM read,
    // S2 RGB composition. Unused diagnostic fields remain hidden.
    // V2.7.7: 5x7 glyph table moved from a large combinational case tree to
    // synchronous block ROM. Address = ASCII[6:0] * 8 + glyph row.
    // The matching pixel/control pipeline is extended by one clock below.
    (* ram_style = "block" *) reg [4:0] glyph_mem [0:1023];
    initial $readmemh("glyph5x7.hex", glyph_mem);



    // S0 captures the character, coordinates, controls and background pixel.
    // The following synchronous font-ROM and RGB stages keep this path bounded.
    reg [7:0] char_q;
    reg [2:0] glyph_row_q, glyph_col_q;
    reg       panel_q, text_q;
    reg [3:0] ui_row_q;
    reg       edge_q, separator_q;
    reg       de_q, sof_q;
    reg [23:0] background_q;

    // Synchronous ROM output (one additional clock compared with glyph()).
    reg [4:0] glyph_bits_q;
    always @(posedge clk)
        glyph_bits_q <= glyph_mem[{char_q[6:0], glyph_row_q}];

    // S1 metadata travels with the synchronous glyph ROM output; S2 composes RGB.
    reg [2:0] glyph_col_1q;
    reg       panel_1q, text_1q, edge_1q, separator_1q, de_1q, sof_1q;
    reg [3:0] ui_row_1q;
    reg [23:0] background_1q;
    wire glyph_on_1q = text_1q && (glyph_col_1q < 3'd5) &&
                       glyph_bits_q[4-glyph_col_1q];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            char_q<=8'h20; glyph_row_q<=0; glyph_col_q<=0;
            panel_q<=0; text_q<=0; ui_row_q<=0;
            edge_q<=0; separator_q<=0;
            de_q<=0; sof_q<=0; background_q<=0;
            glyph_col_1q<=0; panel_1q<=0; text_1q<=0;
            edge_1q<=0; separator_1q<=0; de_1q<=0; sof_1q<=0;
            ui_row_1q<=0; background_1q<=0;
            pixel_out<=0; x<=0; y<=0; display_frame_count<=16'd0;
            ccl_ready_q<=1'b0;
            cam_fault_count_q<=8'd0;
        end else begin
            if (frame_start) begin
                ccl_ready_q <= ccl_ready;
                cam_fault_count_q <= cam_fault_count;
            end
            // S1: synchronous glyph-ROM result and matching S0 metadata.
            glyph_col_1q <= glyph_col_q;
            panel_1q <= panel_q;
            text_1q <= text_q;
            ui_row_1q <= ui_row_q;
            edge_1q <= edge_q;
            separator_1q <= separator_q;
            de_1q <= de_q;
            sof_1q <= sof_q;
            background_1q <= background_q;

            // S0: 文字字符选择 & 视频背景寄存，所有这些信号都与同一像素对应。
            char_q <= get_char(row_index, char_index, row_enabled, feature_enable,
                               latency_cycles, capture_frame_id, display_frame_id,
                               frame_lag_frames, frame_tag_valid,
                               frame_luma, display_frame_count,
                               (SHOW_FRAME_COUNT!=0), algorithm_mode,
                               pv_enable, pv_ae_hold,
                               pv_calibrated, pv_dirty, pv_motion,
                               cam_fault, cam_fault_count_q,
                               ccl_ready_q, ccl_overflow, ccl_overrun);
            glyph_row_q <= glyph_row_index;
            glyph_col_q <= glyph_col_index;
            panel_q <= in_panel;
            text_q <= text_area;
            ui_row_q <= row_index;
            edge_q <= in_panel && ((panel_x==0) || (panel_x==PANEL_W-1) ||
                     (panel_y==0) || (panel_y==PANEL_H-1));
            separator_q <= in_panel && ((panel_y==32) || (panel_y==96) || (panel_y==192) || (panel_y==288));
            de_q <= de;
            sof_q <= frame_start;
            background_q <= pixel_in;

            // S2: compose RGB from synchronous glyph ROM and aligned metadata.
            if (!de_1q || sof_1q) pixel_out<=24'd0;
            else if (panel_1q) begin
                if (edge_1q) pixel_out <= 24'h41617b;
                else if (glyph_on_1q) begin
                    if (ui_row_1q==0) pixel_out<=24'hffffff; // heading
                    else if (ui_row_1q==2) begin
                        if (ccl_overflow || ccl_overrun) pixel_out<=24'hff7878;
                        else if (pv_dirty && pv_enable) pixel_out<=24'hffb263;
                        else if (pv_enable && pv_calibrated) pixel_out<=24'h75e2ae;
                        else pixel_out<=24'hadc6de;
                    end
                    else if (ui_row_1q==9 && (cam_fault || ccl_overflow || ccl_overrun)) pixel_out<=24'hff7878;
                    else if (ui_row_1q==10 && cam_fault) pixel_out<=24'hffb263;
                    else pixel_out<=24'hd4e6f5;
                end else if (separator_1q) pixel_out<=24'h31465d;
                else if (ui_row_1q==0) pixel_out<=24'h1a3950;
                else if (ui_row_1q==2) pixel_out<=24'h183042;
                else if (ui_row_1q==9 || ui_row_1q==10) pixel_out<=24'h172a37;
                else pixel_out<=24'h101f30;
            end else pixel_out<=background_1q;

            // 坐标针对进入 S0 的像素；输出延时不影响坐标计数定义。
            if (frame_start) begin
                x<=0; y<=0;
                display_frame_count<=display_frame_count+1'b1;
            end
            else if (de) begin
                if (line_end) begin
                    x<=0;
                    if (y==IMG_HEIGHT-1) y<=0;
                    else y<=y+1'b1;
                end else if (x==IMG_WIDTH-1) x<=0;
                else x<=x+1'b1;
            end
        end
    end

endmodule
