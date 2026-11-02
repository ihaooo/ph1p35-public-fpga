// SC520CS application key control. The physical KEY1 (D5) is the external
// active-low FPGA reset and must never be remapped here.
//
// buttons_n[0] = KEY2 / A9; buttons_n[1] = KEY3 / B9;
// buttons_n[2] = KEY4 / C7. All buttons are active-low.
//
// Short press (released before LONG_PRESS_CYCLES):
//   KEY2: RGB -> binary -> gray -> Sobel -> RGB
//   KEY3: RGB <-> cartoon (otherwise returns to RGB)
//   KEY4: NO short-press action (AE is controlled by SW1 only)
// Long press: KEY4 event is consumed by vision_pipeline to toggle PV mode.
// Other long-press/chord events are preserved as before.
// Events are one-clock pulses; later features should consume those pulses
// without taking another physical pin or changing this decoder.
//
// Debounce / hold thresholds are clock cycles in the HDMI pixel-clock domain,
// not milliseconds. Defaults target approximately 10 ms / 1 s / 1.5 s at
// 74.25 MHz, and must be adjusted if the actual pixel clock differs.
module vision_key_event_ctrl #(
    parameter integer DEBOUNCE_CYCLES    = 750000,
    parameter integer LONG_PRESS_CYCLES  = 75000000,
    parameter integer CHORD_PRESS_CYCLES = 112500000
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [2:0] buttons_n,
    output reg  [2:0] short_pulse,
    output reg  [2:0] long_pulse,
    output reg        chord_pulse
);
    localparam integer DW = (DEBOUNCE_CYCLES < 2) ? 1 : $clog2(DEBOUNCE_CYCLES);
    localparam integer LW = (LONG_PRESS_CYCLES < 2) ? 1 : $clog2(LONG_PRESS_CYCLES);
    localparam integer PW = (CHORD_PRESS_CYCLES < 2) ? 1 : $clog2(CHORD_PRESS_CYCLES);

    reg [2:0] sync1, sync2, stable, stable_d;
    reg [DW-1:0] debounce_count [0:2];
    reg [LW-1:0] hold_count [0:2];
    reg [2:0] long_fired;
    reg [2:0] suppress_short;
    reg [PW-1:0] chord_count;
    reg chord_fired;
    wire pair_held = !stable[0] && !stable[1];
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync1 <= 3'b111;
            sync2 <= 3'b111;
            stable <= 3'b111;
            stable_d <= 3'b111;
            long_fired <= 3'b000;
            suppress_short <= 3'b000;
            short_pulse <= 3'b000;
            long_pulse <= 3'b000;
            chord_pulse <= 1'b0;
            chord_count <= {PW{1'b0}};
            chord_fired <= 1'b0;
            for (i=0; i<3; i=i+1) begin
                debounce_count[i] <= {DW{1'b0}};
                hold_count[i] <= {LW{1'b0}};
            end
        end else begin
            sync1 <= buttons_n;
            sync2 <= sync1;
            stable_d <= stable;
            short_pulse <= 3'b000;
            long_pulse <= 3'b000;
            chord_pulse <= 1'b0;

            for (i=0; i<3; i=i+1) begin
                // Synchronize and debounce each independent button.
                if (stable[i] != sync2[i]) begin
                    if (debounce_count[i] == DEBOUNCE_CYCLES - 1) begin
                        stable[i] <= sync2[i];
                        debounce_count[i] <= {DW{1'b0}};
                    end else begin
                        debounce_count[i] <= debounce_count[i] + 1'b1;
                    end
                end else begin
                    debounce_count[i] <= {DW{1'b0}};
                end

                // A short press is emitted on *release*. This prevents a
                // long/chord press from also accidentally triggering AE/mode.
                if (stable_d[i] && !stable[i]) begin
                    hold_count[i] <= {LW{1'b0}};
                    long_fired[i] <= 1'b0;
                    suppress_short[i] <= 1'b0;
                end else if (!stable_d[i] && stable[i]) begin
                    if (!long_fired[i] && !suppress_short[i])
                        short_pulse[i] <= 1'b1;
                    hold_count[i] <= {LW{1'b0}};
                    long_fired[i] <= 1'b0;
                    suppress_short[i] <= 1'b0;
                end else if (!stable[i] && !long_fired[i]) begin
                    if (hold_count[i] == LONG_PRESS_CYCLES - 1) begin
                        long_fired[i] <= 1'b1;
                        // Holding both KEY2 and KEY3 suppresses their
                        // individual long-press actions; a separate chord
                        // event is delivered below.
                        if (!suppress_short[i] && !((i < 2) && pair_held))
                            long_pulse[i] <= 1'b1;
                    end else begin
                        hold_count[i] <= hold_count[i] + 1'b1;
                    end
                end
            end

            // Only KEY2 + KEY3 is a chord. Any overlap suppresses both
            // short events; the chord fires once when held long enough.
            // Release BOTH buttons to re-arm the next chord.
            if (pair_held) begin
                suppress_short[0] <= 1'b1;
                suppress_short[1] <= 1'b1;
                if (!chord_fired) begin
                    if (chord_count == CHORD_PRESS_CYCLES - 1) begin
                        chord_pulse <= 1'b1;
                        chord_fired <= 1'b1;
                    end else begin
                        chord_count <= chord_count + 1'b1;
                    end
                end
            end else begin
                chord_count <= {PW{1'b0}};
                if (stable[1:0] == 2'b11)
                    chord_fired <= 1'b0;
            end
        end
    end
endmodule

// Backward-compatible application behavior. Reserved pulses are exported for
// future motion tracking, parameter-menu and OSD diagnostic controllers.
// No reserved event has an action in this revision.
module algorithm_mode_ctrl #(
    parameter integer DEBOUNCE_CYCLES    = 750000,
    parameter integer LONG_PRESS_CYCLES  = 75000000,
    parameter integer CHORD_PRESS_CYCLES = 112500000
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [2:0] buttons_n,
    output reg  [2:0] mode,
    output wire       ae_gate,
    output wire [2:0] reserved_long_event,
    output wire       reserved_chord_event
);
    wire [2:0] key_short_event;
    // Keep the output for compatibility with existing video RTL, but no longer
    // store a key-dependent software AE gate.  SW1 alone controls AE.
    assign ae_gate = 1'b1;

    vision_key_event_ctrl #(
        .DEBOUNCE_CYCLES   (DEBOUNCE_CYCLES),
        .LONG_PRESS_CYCLES (LONG_PRESS_CYCLES),
        .CHORD_PRESS_CYCLES(CHORD_PRESS_CYCLES)
    ) u_key_events (
        .clk(clk),
        .rst_n(rst_n),
        .buttons_n(buttons_n),
        .short_pulse(key_short_event),
        .long_pulse(reserved_long_event),
        .chord_pulse(reserved_chord_event)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mode <= 3'd0;
        end else begin
            if (key_short_event[0]) begin
                case (mode)
                    3'd0: mode <= 3'd1;
                    3'd1: mode <= 3'd2;
                    3'd2: mode <= 3'd3;
                    default: mode <= 3'd0;
                endcase
            end else if (key_short_event[1]) begin
                // KEY3: normal -> cartoon -> film -> normal.
                // KEY3 action retained; KEY4 cannot change AE.
                case (mode)
                    3'd4: mode <= 3'd5;
                    3'd5: mode <= 3'd0;
                    default: mode <= 3'd4;
                endcase
            end
        end
    end
endmodule
