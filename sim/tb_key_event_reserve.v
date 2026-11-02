`timescale 1ns/1ps
// Self-checking reserve-key test. Example (if Icarus Verilog installed):
// iverilog -g2012 -s tb_key_event_reserve -o sim_key.out \
//   rtl/control/mode_ctrl.v sim/tb_key_event_reserve.v
// vvp sim_key.out
module tb_key_event_reserve;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [2:0] buttons_n = 3'b111;
    wire [2:0] mode;
    wire ae_gate;
    wire [2:0] long_evt;
    wire chord_evt;
    integer key2_long_hits = 0;
    integer key3_long_hits = 0;
    integer key4_long_hits = 0;
    integer chord_hits = 0;

    algorithm_mode_ctrl #(
        .DEBOUNCE_CYCLES(2),
        .LONG_PRESS_CYCLES(20),
        .CHORD_PRESS_CYCLES(30)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .buttons_n(buttons_n),
        .mode(mode),
        .ae_gate(ae_gate),
        .reserved_long_event(long_evt),
        .reserved_chord_event(chord_evt)
    );

    always @(posedge clk) begin
        if (rst_n) begin
            if (long_evt[0]) key2_long_hits = key2_long_hits + 1;
            if (long_evt[1]) key3_long_hits = key3_long_hits + 1;
            if (long_evt[2]) key4_long_hits = key4_long_hits + 1;
            if (chord_evt) chord_hits = chord_hits + 1;
        end
    end

    task press_short;
        input integer n;
        begin
            @(negedge clk); buttons_n[n] = 0;
            repeat (9) @(negedge clk);
            buttons_n[n] = 1;
            repeat (10) @(negedge clk);
        end
    endtask

    task press_long;
        input integer n;
        begin
            @(negedge clk); buttons_n[n] = 0;
            repeat (35) @(negedge clk);
            buttons_n[n] = 1;
            repeat (10) @(negedge clk);
        end
    endtask

    task check_state;
        input [2:0] expected_mode;
        input expected_ae;
        begin
            if (mode !== expected_mode || ae_gate !== expected_ae) begin
                $display("FAIL: mode=%0d (want %0d), ae=%b (want %b)",
                         mode, expected_mode, ae_gate, expected_ae);
                $fatal(1);
            end
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        repeat (5) @(negedge clk);
        check_state(0, 1);

        // Existing short actions preserved.
        press_short(0); check_state(1, 1);
        press_short(0); check_state(2, 1);
        press_short(0); check_state(3, 1);
        press_short(0); check_state(0, 1);
        press_short(1); check_state(4, 1);
        press_short(1); check_state(5, 1);
        press_short(1); check_state(0, 1);
        // K4 short does nothing; its long event remains available for PV.
        press_short(2); check_state(0, 1);
        press_short(2); check_state(0, 1);

        // A lone held key fires a reserved event, no legacy short action.
        press_long(0); check_state(0, 1);
        press_long(1); check_state(0, 1);
        press_long(2); check_state(0, 1);
        if (key2_long_hits !== 1 || key3_long_hits !== 1 ||
            key4_long_hits !== 1) begin
            $display("FAIL: long event counts %0d %0d %0d",
                     key2_long_hits, key3_long_hits, key4_long_hits);
            $fatal(1);
        end

        // KEY2 + KEY3 chord: one event, neither KEY2 nor KEY3 short or long.
        @(negedge clk); buttons_n[0] = 0; buttons_n[1] = 0;
        repeat (55) @(negedge clk);
        buttons_n[0] = 1; buttons_n[1] = 1;
        repeat (14) @(negedge clk);
        check_state(0, 1);
        if (chord_hits !== 1 || key2_long_hits !== 1 || key3_long_hits !== 1) begin
            $display("FAIL: chord=%0d long2=%0d long3=%0d",
                     chord_hits, key2_long_hits, key3_long_hits);
            $fatal(1);
        end

        // Partial overlap cannot leak a short event either.
        @(negedge clk); buttons_n[0] = 0;
        repeat (8) @(negedge clk);
        buttons_n[1] = 0;
        repeat (9) @(negedge clk);
        buttons_n[0] = 1;
        repeat (8) @(negedge clk);
        buttons_n[1] = 1;
        repeat (12) @(negedge clk);
        check_state(0, 1);
        if (chord_hits !== 1) $fatal(1, "FAIL: short overlap created a chord");

        // Existing key actions continue working after a chord.
        press_short(0); check_state(1, 1);
        $display("PASS: legacy short keys + reserved long keys + chord isolation");
        $finish;
    end
endmodule
