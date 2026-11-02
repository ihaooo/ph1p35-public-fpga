// Frame-to-frame, noise-guarded global histogram equalization.
// 64 brightness bins, double-buffered histograms and LUTs; no frame buffer.
// Input/output pixel latency remains exactly ONE pixel clock.
//
// V2.7.9 changes:
//  1) Scan the completed histogram before LUT construction and bypass HE for
//     near-uniform/low-contrast scenes (avoids stretching sensor noise).
//  2) Use CDF-min normalization so the first occupied bin maps near black,
//     instead of lifting the entire image by the first-bin population.
//  3) Limit RGB correction to +/-12 luma levels, with a shadow guard and a
//     small correction deadband. Histogram/LUT work stays in blanking periods.
module histogram_equalizer #(
    parameter integer IMG_WIDTH=1280,
    parameter integer IMG_HEIGHT=720
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire        frame_start,
    input  wire        de,
    input  wire [23:0] pixel_in,
    output reg  [23:0] pixel_out
);
    localparam integer PIXEL_COUNT=IMG_WIDTH*IMG_HEIGHT;
    localparam [2:0] ST_INIT=3'd0, ST_IDLE=3'd1,
                     ST_SCAN=3'd2, ST_BUILD=3'd3, ST_CLEAR=3'd4;
    localparam [5:0] MIN_HE_SPAN_BINS=6'd8; // 8 bins ~= 32 luma levels

    reg [2:0] state;
    reg [19:0] hist_a[0:63];
    reg [19:0] hist_b[0:63];
    reg [7:0] lut_a[0:63];
    reg [7:0] lut_b[0:63];
    reg [6:0] idx;
    reg started;
    reg hist_active;
    reg hist_source;
    reg lut_active;
    reg lut_dest;
    reg lut_ready;
    reg lut_valid;
    reg [20:0] cdf;
    reg [20:0] cdf_min;
    reg cdf_min_valid;

    // The scan pass finds the occupied-bin span of the completed frame.
    // Since bins are scanned from low to high, the first occupied bin is min
    // and the last occupied bin is max. A narrow span is not equalized.
    reg [5:0] first_bin;
    reg [5:0] last_bin;
    reg hist_nonzero;
    wire [5:0] occupied_span = last_bin - first_bin;
    wire scene_low_contrast = (!hist_nonzero) ||
                              (occupied_span < MIN_HE_SPAN_BINS);

    // BT.601 luma (77R + 150G + 29B) / 256, implemented with shifts/adds.
    wire [7:0] r=pixel_in[23:16];
    wire [7:0] g=pixel_in[15:8];
    wire [7:0] b=pixel_in[7:0];
    wire [16:0] sum=
        ({9'd0,r}<<6)+({9'd0,r}<<3)+({9'd0,r}<<2)+r+
        ({9'd0,g}<<7)+({9'd0,g}<<4)+({9'd0,g}<<2)+({9'd0,g}<<1)+
        ({9'd0,b}<<4)+({9'd0,b}<<3)+({9'd0,b}<<2)+b;
    wire [7:0] gray=sum[15:8];
    wire [5:0] bin=gray[7:2];
    wire [7:0] lookup=lut_active ? lut_b[bin] : lut_a[bin];

    // Histogram source is the completed bank. The active bank is swapped at
    // frame start, so it can count the new frame while this bank is scanned.
    wire [20:0] bin_count=hist_source ?
        {1'b0,hist_b[idx[5:0]]} : {1'b0,hist_a[idx[5:0]]};

    // CDF-min: subtract the population of the first occupied bin before
    // mapping. This prevents a dark/mostly uniform histogram from lifting all
    // pixels just because its first occupied bin contains many samples.
    wire [20:0] cdf_next=cdf+bin_count;
    wire [20:0] cdf_adjusted =
        (cdf_min_valid && (cdf_next > cdf_min)) ?
        (cdf_next-cdf_min) : 21'd0;
    // For 1280x720, 255 / 921600 ~= 290 / 2^20. This multiply is only used
    // during LUT construction in blanking; it is not in the per-pixel path.
    wire [29:0] map_product=cdf_adjusted*9'd290;
    wire [9:0] mapped=map_product[29:20];
    wire [7:0] mapped_lut=(mapped>10'd255) ? 8'hff : mapped[7:0];

    // Noise-safe HE strength. Large global remaps are intentionally reduced:
    // +/-12 levels in normal regions, +/-6 in shadows, and no correction for
    // near-black pixels. Differences of <=3 levels are treated as a deadband.
    localparam signed [10:0] MAX_HE_DELTA = 11'sd48;
    wire signed [10:0] delta_raw =
        $signed({3'b000,lookup}) - $signed({3'b000,gray});
    wire signed [10:0] delta_clip =
        (delta_raw > MAX_HE_DELTA) ? MAX_HE_DELTA :
        (delta_raw < -MAX_HE_DELTA) ? -MAX_HE_DELTA : delta_raw;
    wire signed [9:0] delta_strength =
        (gray < 8'd64) ? (delta_clip >>> 3) : (delta_clip >>> 2);
    wire signed [9:0] delta =
        (gray < 8'd24) ? 10'sd0 :
        ((delta_raw >= -11'sd3) && (delta_raw <= 11'sd3)) ? 10'sd0 :
        delta_strength;

    function [7:0] add_clamped;
        input [7:0] original;
        input signed [9:0] offset;
        reg signed [10:0] extended;
        begin
            extended=$signed({3'b000,original})+offset;
            if (extended < 0) add_clamped=8'd0;
            else if (extended > 255) add_clamped=8'd255;
            else add_clamped=extended[7:0];
        end
    endfunction
    wire [23:0] enhanced={add_clamped(r,delta),
                           add_clamped(g,delta),
                           add_clamped(b,delta)};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_out<=24'd0;
            state<=ST_INIT;
            idx<=7'd0;
            started<=1'b0;
            hist_active<=1'b0;
            hist_source<=1'b0;
            lut_active<=1'b0;
            lut_dest<=1'b1;
            lut_ready<=1'b0;
            lut_valid<=1'b0;
            cdf<=21'd0;
            cdf_min<=21'd0;
            cdf_min_valid<=1'b0;
            first_bin<=6'd63;
            last_bin<=6'd0;
            hist_nonzero<=1'b0;
        end else begin
            // Keep the established one-clock pixel alignment and bypass path.
            pixel_out<=(!de) ? 24'd0 :
                       (!enable || !lut_valid) ? pixel_in : enhanced;

            if (state==ST_INIT) begin
                hist_a[idx[5:0]]<=20'd0;
                hist_b[idx[5:0]]<=20'd0;
                lut_a[idx[5:0]]<={idx[5:0],2'b10};
                lut_b[idx[5:0]]<={idx[5:0],2'b10};
                if (idx==7'd63) begin
                    idx<=7'd0;
                    state<=ST_IDLE;
                end else idx<=idx+1'b1;
            end else begin
                // Frame boundary starts a three-pass blanking-time operation:
                // scan histogram -> build LUT -> clear consumed histogram.
                if (frame_start) begin
                    if (!started) begin
                        started<=1'b1;
                    end else begin
                        hist_source<=hist_active;
                        hist_active<=~hist_active;
                        idx<=7'd0;
                        cdf<=21'd0;
                        cdf_min<=21'd0;
                        cdf_min_valid<=1'b0;
                        first_bin<=6'd63;
                        last_bin<=6'd0;
                        hist_nonzero<=1'b0;
                        state<=ST_SCAN;
                        // Publish only a complete LUT, at a frame boundary.
                        if (lut_ready) begin
                            lut_active<=~lut_active;
                            lut_dest<=lut_active;
                            lut_valid<=1'b1;
                        end else begin
                            lut_dest<=~lut_active;
                        end
                        lut_ready<=1'b0;
                    end
                end else begin
                    // Count only into the active bank, never into the bank
                    // currently being scanned, mapped, or cleared.
                    if (de && started) begin
                        if (hist_active)
                            hist_b[bin]<=hist_b[bin]+1'b1;
                        else
                            hist_a[bin]<=hist_a[bin]+1'b1;
                    end

                    if (!de) begin
                        if (state==ST_SCAN) begin
                            if (bin_count != 21'd0) begin
                                if (!hist_nonzero) first_bin<=idx[5:0];
                                last_bin<=idx[5:0];
                                hist_nonzero<=1'b1;
                            end
                            if (idx==7'd63) begin
                                idx<=7'd0;
                                cdf<=21'd0;
                                cdf_min<=21'd0;
                                cdf_min_valid<=1'b0;
                                state<=ST_BUILD;
                            end else idx<=idx+1'b1;
                        end else if (state==ST_BUILD) begin
                            if (scene_low_contrast) begin
                                // Identity LUT for flat scenes: do not amplify
                                // noise when the occupied luma range is narrow.
                                if (lut_dest)
                                    lut_b[idx[5:0]]<={idx[5:0],2'b10};
                                else
                                    lut_a[idx[5:0]]<={idx[5:0],2'b10};
                            end else begin
                                if (!cdf_min_valid && (bin_count != 21'd0)) begin
                                    cdf_min<=cdf_next;
                                    cdf_min_valid<=1'b1;
                                end
                                if (lut_dest)
                                    lut_b[idx[5:0]]<=mapped_lut;
                                else
                                    lut_a[idx[5:0]]<=mapped_lut;
                            end
                            cdf<=cdf_next;
                            if (idx==7'd63) begin
                                idx<=7'd0;
                                lut_ready<=1'b1;
                                state<=ST_CLEAR;
                            end else idx<=idx+1'b1;
                        end else if (state==ST_CLEAR) begin
                            if (hist_source)
                                hist_b[idx[5:0]]<=20'd0;
                            else
                                hist_a[idx[5:0]]<=20'd0;
                            if (idx==7'd63) begin
                                idx<=7'd0;
                                state<=ST_IDLE;
                            end else idx<=idx+1'b1;
                        end
                    end
                end
            end
        end
    end
endmodule
