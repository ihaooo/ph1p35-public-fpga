// V2.7.8: 8x7segment uses the signal polarity demonstrated by the
// uploaded HX1P35A static and scan sample projects, NOT the older manual prose.
// DIG[7:0] = {DP,g,f,e,d,c,b,a}, segment ON is LOW.
// SEL[7:0] digit SELECT is LOW (official sm_scan.v: 8'b1111_1110).
// BUZZER is active LOW through transistor; SW5 is a hardware mute switch.
module pv_board_io_ctrl #(
    parameter integer CLK_HZ = 74250000,
    parameter integer DIGIT_REFRESH_HZ = 1000,
    // Alarm envelope: two short beeps, then a long beep, then a pause.
    parameter integer SIREN_SHORT_ON_MS  = 120,
    parameter integer SIREN_SHORT_OFF_MS = 95,
    parameter integer SIREN_LONG_ON_MS   = 340,
    parameter integer SIREN_REST_MS      = 540,
    // Noise-resistant actuator/buzzer decision (measured in display frames).
    parameter integer DIRTY_CONFIRM_FRAMES = 3,
    parameter integer CLEAN_CONFIRM_FRAMES = 6,
    parameter integer SELF_TEST_PATTERN = 0,
    parameter integer SEL_ACTIVE_LOW = 1,
    // Board default: active buzzer (DC LOW during ON phase).
    // For passive buzzer only: set PASSIVE_TONE_ENABLE=1.
    parameter integer PASSIVE_TONE_ENABLE = 0,
    parameter integer PASSIVE_TONE_LOW_HZ  = 1350,
    parameter integer PASSIVE_TONE_HIGH_HZ = 2050
)(
    input wire clk,
    input wire rst_n,
    input wire frame_start,
    input wire [2:0] algorithm_mode,
    input wire pv_enable,
    input wire pv_calibrated,
    input wire pv_dirty,
    input wire [2:0] object_count,
    input wire ccl_fault,
    output wire buzzer_n,
    output wire servo_alarm,
    output reg [7:0] dig,
    output reg [7:0] sel
);
    // Target: each digit receives 1000 strobes / second (8 kHz overall).
    localparam integer SCAN_DIV_RAW = CLK_HZ / (8 * DIGIT_REFRESH_HZ);
    localparam integer SCAN_DIV = (SCAN_DIV_RAW < 3) ? 3 : SCAN_DIV_RAW;
    localparam integer SCAN_CNT_W = $clog2(SCAN_DIV);
    reg [SCAN_CNT_W-1:0] scan_divider;
    reg [2:0] scan_index;
    reg [1:0] scan_stage; // 0: steady; 1: set new DIG; 2: enable new SEL
    reg [7:0] selected_char;
    reg [7:0] selected_seg;
    wire scan_tick = (scan_divider == SCAN_DIV-1);

    localparam [2:0] ST_OFF=0, ST_SETUP=1, ST_CLEAN=2,
                     ST_DIRTY=3, ST_ERROR=4;
    reg [2:0] mode_q;
    reg [2:0] status_q;
    reg [2:0] count_q;
    // 'pv_dirty' already excludes CAM ERR in vision_pipeline; ccl_fault
    // independently gates output on CAM ERR/CCL-overflow with no added frame delay.
    wire monitor_ok = pv_enable && pv_calibrated && !ccl_fault;
    wire dirty_sample = monitor_ok && pv_dirty;
    reg alarm_latched;
    reg [7:0] dirty_frames;
    reg [7:0] clean_frames;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alarm_latched <= 1'b0;
            dirty_frames <= 0;
            clean_frames <= 0;
        end else if (!monitor_ok) begin
            alarm_latched <= 1'b0;
            dirty_frames <= 0;
            clean_frames <= 0;
        end else if (frame_start) begin
            if (dirty_sample) begin
                clean_frames <= 0;
                if (!alarm_latched) begin
                    if (dirty_frames >= DIRTY_CONFIRM_FRAMES-1) begin
                        alarm_latched <= 1'b1;
                        dirty_frames <= 0;
                    end else dirty_frames <= dirty_frames + 1'b1;
                end
            end else begin
                dirty_frames <= 0;
                if (alarm_latched) begin
                    if (clean_frames >= CLEAN_CONFIRM_FRAMES-1) begin
                        alarm_latched <= 1'b0;
                        clean_frames <= 0;
                    end else clean_frames <= clean_frames + 1'b1;
                end
            end
        end
    end
    assign servo_alarm = alarm_latched && monitor_ok;

    // Mode changes immediately; PV status/box count are frame snapshots.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            mode_q <= 0;
            status_q <= ST_OFF;
            count_q <= 0;
        end else begin
            mode_q <= algorithm_mode;
            if(frame_start) begin
                if(!pv_enable) begin
                    status_q <= ST_OFF; count_q <= 0;
                end else if(ccl_fault) begin
                    status_q <= ST_ERROR; count_q <= 0;
                end else if(!pv_calibrated) begin
                    status_q <= ST_SETUP; count_q <= 0;
                end else if(pv_dirty) begin
                    status_q <= ST_DIRTY; count_q <= object_count;
                end else begin
                    status_q <= ST_CLEAN; count_q <= 0;
                end
            end
        end
    end

    // The official scan demo selects with LOW, so SEL=8'hFF blanks ALL digits.
    // At a tick, blank OLD digit; next clock set segment data; next clock
    // enable exactly ONE NEW digit. No two digits are selected simultaneously.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            scan_divider <= 0;
            scan_index   <= 3'd7; // First tick starts from leftmost index 0.
            scan_stage   <= 0;
            dig <= 8'hFF;
            sel <= SEL_ACTIVE_LOW ? 8'hFF : 8'h00;
        end else if(scan_tick) begin
            scan_divider <= 0;
            sel <= SEL_ACTIVE_LOW ? 8'hFF : 8'h00;
            scan_index <= scan_index + 1'b1;
            scan_stage <= 2'd1;
        end else begin
            scan_divider <= scan_divider + 1'b1;
            if(scan_stage == 2'd1) begin
                dig <= selected_seg;
                scan_stage <= 2'd2;
            end else if(scan_stage == 2'd2) begin
                sel <= SEL_ACTIVE_LOW ? ~(8'b0000_0001 << scan_index)
                                      :  (8'b0000_0001 << scan_index);
                scan_stage <= 2'd0;
            end
        end
    end

    // Siren envelope. We reuse the 8-kHz seven-segment scan tick and
    // count approximately 8 ticks per millisecond, avoiding a new wide
    // 74.25-MHz millisecond timer. All division below is elaboration-time.
    localparam integer SCANS_PER_MS_RAW = CLK_HZ / (SCAN_DIV * 1000);
    localparam integer SCANS_PER_MS = (SCANS_PER_MS_RAW < 1) ? 1 : SCANS_PER_MS_RAW;
    localparam integer MILLIS_CNT_W = (SCANS_PER_MS < 2) ? 1 : $clog2(SCANS_PER_MS);
    reg [MILLIS_CNT_W-1:0] scan_ms_count;
    wire ms_tick = scan_tick && (scan_ms_count == SCANS_PER_MS-1);
    wire siren_request = servo_alarm;
    reg siren_running_d;
    reg [2:0] siren_phase;
    reg [11:0] phase_elapsed_ms;
    reg [11:0] phase_duration_ms;
    always @* begin
        case (siren_phase)
            3'd0,3'd2: phase_duration_ms = SIREN_SHORT_ON_MS;
            3'd1,3'd3: phase_duration_ms = SIREN_SHORT_OFF_MS;
            3'd4:      phase_duration_ms = SIREN_LONG_ON_MS;
            default:   phase_duration_ms = SIREN_REST_MS;
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_ms_count <= 0;
            siren_running_d <= 0;
            siren_phase <= 0;
            phase_elapsed_ms <= 0;
        end else begin
            siren_running_d <= siren_request;
            if (!siren_request) begin
                scan_ms_count <= 0;
                siren_phase <= 0;
                phase_elapsed_ms <= 0;
            end else if (!siren_running_d) begin
                scan_ms_count <= 0;
                siren_phase <= 0;
                phase_elapsed_ms <= 0;
            end else if (scan_tick) begin
                if (ms_tick) begin
                    scan_ms_count <= 0;
                    if (phase_elapsed_ms >= phase_duration_ms-1) begin
                        phase_elapsed_ms <= 0;
                        if (siren_phase == 3'd5) siren_phase <= 0;
                        else siren_phase <= siren_phase + 1'b1;
                    end else phase_elapsed_ms <= phase_elapsed_ms + 1'b1;
                end else scan_ms_count <= scan_ms_count + 1'b1;
            end
        end
    end
    // Three on periods: short/short/long. The third burst may also change
    // pitch on PASSIVE buzzers. The BOARD default is an ACTIVE buzzer:
    // active buzzers already oscillate internally; we only gate their power.
    wire siren_burst_on = (siren_phase==3'd0 || siren_phase==3'd2 || siren_phase==3'd4);
    wire tone_high = (siren_phase==3'd2) ||
                     ((siren_phase==3'd4) &&
                      (phase_elapsed_ms >= SIREN_LONG_ON_MS/2));
    wire tone_wave;
    generate if(PASSIVE_TONE_ENABLE != 0) begin: g_passive
        localparam integer DIV_LOW_RAW  = CLK_HZ/(2*PASSIVE_TONE_LOW_HZ);
        localparam integer DIV_HIGH_RAW = CLK_HZ/(2*PASSIVE_TONE_HIGH_HZ);
        localparam integer DIV_LOW  = (DIV_LOW_RAW  < 2) ? 2 : DIV_LOW_RAW;
        localparam integer DIV_HIGH = (DIV_HIGH_RAW < 2) ? 2 : DIV_HIGH_RAW;
        localparam integer DIV_MAX  = (DIV_LOW > DIV_HIGH) ? DIV_LOW : DIV_HIGH;
        localparam integer TW = (DIV_MAX < 2) ? 1 : $clog2(DIV_MAX);
        reg [TW-1:0] tone_counter;
        reg tone_q;
        reg tone_high_d;
        wire [TW-1:0] tone_div = tone_high ? DIV_HIGH : DIV_LOW;
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                tone_counter<=0; tone_q<=0; tone_high_d<=0;
            end else begin
                tone_high_d <= tone_high;
                if (!siren_request || tone_high_d != tone_high) begin
                    tone_counter <= 0;
                    tone_q <= 1'b0;
                end else if (tone_counter >= tone_div-1) begin
                    tone_counter<=0; tone_q<=~tone_q;
                end else tone_counter<=tone_counter+1'b1;
            end
        end
        assign tone_wave = tone_q;
    end else begin: g_active
        assign tone_wave = 1'b1;
    end endgenerate
    assign buzzer_n = ~(siren_request && siren_burst_on && tone_wave);

    function [7:0] mode_char;
        input [2:0] mode;
        begin
            case (mode)
                3'd0: mode_char = 8'h72; // r: RGB/normal
                3'd1: mode_char = 8'h62; // b: binary
                3'd2: mode_char = 8'h67; // g: gray
                3'd3: mode_char = 8'h53; // S: Sobel
                3'd4: mode_char = 8'h43; // C: cartoon
                3'd5: mode_char = 8'h46; // F: film
                default: mode_char = 8'h2d; // -
            endcase
        end
    endfunction

    function [7:0] status_char;
        input [2:0] state;
        input       second_char;
        begin
            case (state)
                ST_OFF:   status_char = second_char ? 8'h46 : 8'h4f; // OF
                ST_SETUP: status_char = second_char ? 8'h45 : 8'h53; // SE
                ST_CLEAN: status_char = second_char ? 8'h4c : 8'h43; // CL
                ST_DIRTY: status_char = second_char ? 8'h59 : 8'h64; // dY
                ST_ERROR: status_char = second_char ? 8'h72 : 8'h45; // Er
                default:  status_char = 8'h2d;
            endcase
        end
    endfunction

    function [7:0] seven_seg;
        input [7:0] ch;
        begin
            // Output bit order {DP,g,f,e,d,c,b,a}; common-anode, active low.
            case (ch)
                8'h30: seven_seg=8'hC0; // 0
                8'h31: seven_seg=8'hF9; // 1
                8'h32: seven_seg=8'hA4; // 2
                8'h33: seven_seg=8'hB0; // 3
                8'h34: seven_seg=8'h99; // 4
                8'h35: seven_seg=8'h92; // 5
                8'h36: seven_seg=8'h82; // 6
                8'h37: seven_seg=8'hF8; // 7
                8'h38: seven_seg=8'h80; // 8
                8'h39: seven_seg=8'h90; // 9
                8'h50: seven_seg=8'h8C; // P
                8'h56: seven_seg=8'hC1; // V approximated as U
                8'h72: seven_seg=8'hAF; // r
                8'h62: seven_seg=8'h83; // b
                8'h67: seven_seg=8'h82; // g approximated as 6
                8'h53: seven_seg=8'h92; // S
                8'h43: seven_seg=8'hC6; // C
                8'h46: seven_seg=8'h8E; // F
                8'h4f: seven_seg=8'hC0; // O
                8'h45: seven_seg=8'h86; // E
                8'h4c: seven_seg=8'hC7; // L
                8'h64: seven_seg=8'hA1; // d
                8'h59: seven_seg=8'h91; // Y approximated
                8'h6e: seven_seg=8'hAB; // n
                8'h2d: seven_seg=8'hBF; // -
                default: seven_seg=8'hFF; // blank
            endcase
        end
    endfunction

    always @* begin
        // Official dynamic demo uses first (leftmost) slot 0 through slot 7.
        // Display: [mode letter][mode digit][state0][state1] n 0 0 [count]
        case (scan_index)
            3'd0: selected_char = mode_char(mode_q);
            3'd1: selected_char = 8'h30 + {5'b0,mode_q};
            3'd2: selected_char = status_char(status_q,1'b0);
            3'd3: selected_char = status_char(status_q,1'b1);
            3'd4: selected_char = 8'h6e; // n: count label
            3'd5: selected_char = 8'h30;
            3'd6: selected_char = 8'h30;
            3'd7: selected_char = 8'h30 + {5'b0,count_q};
            default: selected_char = 8'h20;
        endcase
        if(SELF_TEST_PATTERN != 0)
            selected_char = 8'h30 + {5'b0,scan_index}; // 01234567
        selected_seg = seven_seg(selected_char);
    end
endmodule
