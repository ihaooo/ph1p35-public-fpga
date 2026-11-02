// V2.8.3: Low-resource 16x16 *spatial blocks* gray-point AWB, DISPLAY ONLY.
// 1280x720 -> 16 columns by 16 rows (80x45 source pixels each).
// - One RGB sample per 4x4 pixels, with per-block 256x56-bit sync RAM.
// - During vertical blank scan each block's mean for neutral and mid-tone cues.
// - Sum eligible neutral blocks, compute Q8 G/R and G/B ratios with a
//   serialized shift/subtract divider (10 bits, no wide / in hardware).
// - Clamp Q8 gains to [128,512], slew <=8 Q8 units per update, 4-frame rate.
// - Exactly ONE registered pixel stage; de/sof/eol must be delayed one stage
//   by the caller as in the previous V2.8.2 design.
// - Never feed this output into the PV detection reference or mask path.
// This is a BRAM *inference attempt*. Check TD gate map for actual ERAM use.
module auto_white_balance #(
    parameter integer IMG_WIDTH=1280,
    parameter integer IMG_HEIGHT=720,
    parameter integer GAIN_MIN=128,    // 0.5 x, Q8
    parameter integer GAIN_MAX=512,    // 2.0 x, Q8
    parameter integer MAX_GAIN_SLEW=8, // max 1/32 change per AWB update
    parameter integer MIN_GRAY_BLOCKS=8,
    parameter integer MIN_CELL_SAMPLES=16,
    parameter integer UPDATE_EVERY_FRAMES=4
)(
    input wire clk, input wire rst_n, input wire enable,
    input wire stats_enable,  // low during CAM ERR: ignore stale/replayed frames
    input wire frame_start, input wire line_end, input wire de,
    input wire [23:0] pixel_in,
    output reg [23:0] pixel_out
);
    localparam integer TILE_W = IMG_WIDTH / 16;
    localparam integer TILE_H = IMG_HEIGHT / 16;
    // RAM word: {count[7:0], sumR[15:0], sumG[15:0], sumB[15:0]}
    reg [55:0] gray_block_mem [0:255];
    reg [55:0] block_q;
    reg [7:0] mem_rd_addr, mem_wr_addr;
    reg [55:0] mem_wr_data;
    reg mem_re, mem_we;
    always @(posedge clk) begin
        if (mem_we) gray_block_mem[mem_wr_addr] <= mem_wr_data;
        if (mem_re) block_q <= gray_block_mem[mem_rd_addr];
    end

    localparam [3:0] ST_CLEAR=4'd0, ST_WAIT=4'd1, ST_COLLECT=4'd2,
                     ST_SCAN_RD=4'd3, ST_SCAN_CHECK=4'd4,
                     ST_SCAN_ZERO=4'd5, ST_DIV_R=4'd6,
                     ST_DIV_R_DONE=4'd7, ST_DIV_B=4'd8,
                     ST_COMMIT=4'd9;
    reg [3:0] state;
    reg [7:0] index_q;
    reg [10:0] col_in_tile;
    reg [9:0] row_in_tile;
    reg [3:0] col_tile, row_tile;

    wire stream_start = (state==ST_WAIT) && frame_start && stats_enable;
    wire running = (state==ST_COLLECT) || stream_start;
    wire [10:0] sx = frame_start ? 11'd0 : col_in_tile;
    wire [9:0] sy = frame_start ? 10'd0 : row_in_tile;
    wire [7:0] sample_addr = frame_start ? 8'd0 : {row_tile,col_tile};
    wire sample_now = running && stats_enable && de &&
                      (sx[1:0]==2'b00) && (sy[1:0]==2'b00);
    reg s1, s2;
    reg [7:0] s1_addr, s1_r,s1_g,s1_b;
    reg [7:0] s2_addr;
    reg [55:0] s2_word;
    wire [7:0] old_count=block_q[55:48];
    wire [15:0] old_r=block_q[47:32], old_g=block_q[31:16], old_b=block_q[15:0];

    reg [23:0] neutral_r, neutral_g, neutral_b;
    reg [8:0] neutral_blocks;
    reg [2:0] frame_mod;
    reg [9:0] gain_r_q8,gain_b_q8;
    reg [9:0] target_r_q8;
    reg [33:0] rem_q, divisor_q;
    reg [9:0] quotient_q;
    reg [3:0] div_index;
    // Compare whole-block *averages* without dynamic division.
    // 30, 50, 200 are constants implemented using shifts and additions.
    wire [7:0] bc = block_q[55:48];
    wire [15:0] br = block_q[47:32], bg=block_q[31:16], bb=block_q[15:0];
    wire [16:0] diff_rg=br>=bg ? {1'b0,br}-{1'b0,bg} : {1'b0,bg}-{1'b0,br};
    wire [16:0] diff_gb=bg>=bb ? {1'b0,bg}-{1'b0,bb} : {1'b0,bb}-{1'b0,bg};
    wire [16:0] delta_max = ({9'd0,bc} << 5) - ({9'd0,bc} << 1); // 30*cnt
    wire [17:0] lum_four = {2'd0,br} + ({2'd0,bg} << 1) + {2'd0,bb};
    wire [17:0] min_lum4=({10'd0,bc} << 7)+({10'd0,bc} << 6)+({10'd0,bc} << 3); // 200*cnt =4*50*cnt
    wire [17:0] max_lum4=({10'd0,bc} << 9)+({10'd0,bc} << 8)+({10'd0,bc} << 5); // 800*cnt
    // mean luminance ≈ (R+2G+B)/(4*count), accepted 50..200.
    wire neutral_valid=(bc>=MIN_CELL_SAMPLES) &&
         (diff_rg<delta_max) && (diff_gb<delta_max) &&
         (lum_four>=min_lum4) && (lum_four<=max_lum4);
    // (200*cnt) and (800*cnt) are 4x average-luminance bounds.

    // Sequential Q8 divider: floor((sumG<<8)/sumR) and same for B.
    // Largest possible accepted frame sums: 256*240*255 < 2^24.
    wire [9:0] gain_limited = quotient_q<GAIN_MIN ? GAIN_MIN[9:0] :
                              quotient_q>GAIN_MAX ? GAIN_MAX[9:0] : quotient_q;
    function [9:0] smooth_gain;
        input [9:0] old_gain, desired;
        reg [9:0] diff, step;
        begin
            if (desired > old_gain + 10'd3) begin
                diff=desired-old_gain;
                step=(diff+10'd7)>>3;
                if (step>MAX_GAIN_SLEW) step=MAX_GAIN_SLEW;
                smooth_gain=old_gain+step;
            end else if (old_gain > desired+10'd3) begin
                diff=old_gain-desired;
                step=(diff+10'd7)>>3;
                if (step>MAX_GAIN_SLEW) step=MAX_GAIN_SLEW;
                smooth_gain=old_gain-step;
            end else smooth_gain=old_gain;
        end
    endfunction
    function [7:0] scale;
        input [7:0] pixel;
        input [9:0] gain;
        reg [17:0] prod;
        begin
            prod=pixel*gain;
            if (prod >= 18'd65280) scale=8'hff;
            else scale=prod[15:8];
        end
    endfunction

    // RGB correction is always a one-cycle registered pass-through when off.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) pixel_out<=24'd0;
        else if (!de) pixel_out<=24'd0;
        else if (!enable) pixel_out<=pixel_in;
        else pixel_out<={scale(pixel_in[23:16],gain_r_q8),
                          pixel_in[15:8],scale(pixel_in[7:0],gain_b_q8)};
    end

    always @(*) begin
        mem_re=1'b0; mem_we=1'b0;
        mem_rd_addr=8'd0; mem_wr_addr=8'd0;
        mem_wr_data=56'd0;
        if (state==ST_CLEAR) begin
            mem_we=1'b1; mem_wr_addr=index_q;
        end else if (state==ST_SCAN_RD) begin
            mem_re=1'b1; mem_rd_addr=index_q;
        end else if (state==ST_SCAN_ZERO) begin
            mem_we=1'b1; mem_wr_addr=index_q;
        end else if (s2 && state==ST_COLLECT) begin
            mem_we=1'b1; mem_wr_addr=s2_addr; mem_wr_data=s2_word;
        end else if (sample_now) begin
            mem_re=1'b1; mem_rd_addr=sample_addr;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=ST_CLEAR; index_q<=8'd0;
            col_in_tile<=0; row_in_tile<=0; col_tile<=0; row_tile<=0;
            s1<=0;s2<=0;s1_addr<=0;s1_r<=0;s1_g<=0;s1_b<=0;
            s2_addr<=0;s2_word<=0;
            neutral_r<=0;neutral_g<=0;neutral_b<=0;neutral_blocks<=0;
            frame_mod<=0;gain_r_q8<=10'd256;gain_b_q8<=10'd256;
            target_r_q8<=10'd256;
            rem_q<=0;divisor_q<=0;quotient_q<=0;div_index<=0;
        end else begin
            s1<=sample_now;
            s2<=s1;
            if(sample_now) begin
                s1_addr<=sample_addr;
                s1_r<=pixel_in[23:16];s1_g<=pixel_in[15:8];s1_b<=pixel_in[7:0];
            end
            if(s1) begin
                s2_addr<=s1_addr;
                s2_word<={old_count+8'd1, old_r+{8'd0,s1_r},
                          old_g+{8'd0,s1_g}, old_b+{8'd0,s1_b}};
            end
            if(!enable) begin gain_r_q8<=10'd256;gain_b_q8<=10'd256;end

            // Horizontal and vertical tile counters (no divide/modulo hardware).
            if (running && stats_enable) begin
                if (frame_start) begin
                    col_in_tile<=de?11'd1:11'd0;
                    row_in_tile<=10'd0;
                    col_tile<=4'd0;row_tile<=4'd0;
                end else begin
                    if(de) begin
                        if (col_in_tile==TILE_W-1) begin
                            col_in_tile<=0;
                            col_tile<=col_tile+4'd1;
                        end else col_in_tile<=col_in_tile+11'd1;
                    end
                    if(line_end) begin
                        col_in_tile<=0;col_tile<=0;
                        if(row_in_tile==TILE_H-1) begin
                            row_in_tile<=0;
                            row_tile<=row_tile+4'd1;
                        end else row_in_tile<=row_in_tile+10'd1;
                    end
                end
            end

            if (!stats_enable && state!=ST_CLEAR && state!=ST_WAIT) begin
                state<=ST_CLEAR;index_q<=0;neutral_r<=0;neutral_g<=0;
                neutral_b<=0;neutral_blocks<=0;frame_mod<=0;
                s1<=0;s2<=0;
            end else begin
                case(state)
                    ST_CLEAR: begin
                        if(index_q==8'hff) begin
                            index_q<=0;
                            state<=ST_WAIT;
                        end else index_q<=index_q+8'd1;
                    end
                    ST_WAIT: begin
                        if(stream_start) begin
                            state<=ST_COLLECT;
                            neutral_r<=0;neutral_g<=0;neutral_b<=0;
                            neutral_blocks<=0;
                        end
                    end
                    ST_COLLECT: begin
                        if(line_end && (row_tile==4'd15) && (row_in_tile==TILE_H-1)) begin
                            index_q<=0;
                            state<=ST_SCAN_RD;
                        end
                    end
                    ST_SCAN_RD: state<=ST_SCAN_CHECK;
                    ST_SCAN_CHECK: begin
                        if(neutral_valid) begin
                            neutral_r<=neutral_r+{8'd0,br};
                            neutral_g<=neutral_g+{8'd0,bg};
                            neutral_b<=neutral_b+{8'd0,bb};
                            neutral_blocks<=neutral_blocks+9'd1;
                        end
                        state<=ST_SCAN_ZERO;
                    end
                    ST_SCAN_ZERO: begin
                        if(index_q==8'hff) begin
                            index_q<=0;
                            if((neutral_blocks>=MIN_GRAY_BLOCKS) &&
                               (neutral_r!=0) && (neutral_b!=0) &&
                               (frame_mod==UPDATE_EVERY_FRAMES-1) && enable) begin
                                frame_mod<=0;
                                rem_q<={2'd0,neutral_g,8'd0};
                                divisor_q<={1'b0,neutral_r,9'd0};
                                quotient_q<=0;div_index<=4'd9;
                                state<=ST_DIV_R;
                            end else begin
                                if(frame_mod==UPDATE_EVERY_FRAMES-1) frame_mod<=0;
                                else frame_mod<=frame_mod+3'd1;
                                state<=ST_WAIT;
                            end
                        end else begin index_q<=index_q+8'd1;state<=ST_SCAN_RD;end
                    end
                    ST_DIV_R: begin
                        if(rem_q>=divisor_q) begin
                            rem_q<=rem_q-divisor_q;
                            quotient_q[div_index]<=1'b1;
                        end
                        divisor_q<=divisor_q>>1;
                        if(div_index==0) state<=ST_DIV_R_DONE;
                        else div_index<=div_index-4'd1;
                    end
                    ST_DIV_R_DONE: begin
                        target_r_q8<=gain_limited;
                        rem_q<={2'd0,neutral_g,8'd0};
                        divisor_q<={1'b0,neutral_b,9'd0};
                        quotient_q<=0;div_index<=4'd9;
                        state<=ST_DIV_B;
                    end
                    ST_DIV_B: begin
                        if(rem_q>=divisor_q) begin
                            rem_q<=rem_q-divisor_q;
                            quotient_q[div_index]<=1'b1;
                        end
                        divisor_q<=divisor_q>>1;
                        if(div_index==0) state<=ST_COMMIT;
                        else div_index<=div_index-4'd1;
                    end
                    ST_COMMIT: begin
                        if(enable && stats_enable) begin
                            gain_r_q8<=smooth_gain(gain_r_q8,target_r_q8);
                            gain_b_q8<=smooth_gain(gain_b_q8,gain_limited);
                        end
                        state<=ST_WAIT;
                    end
                    default: state<=ST_CLEAR;
                endcase
            end
        end
    end
endmodule
