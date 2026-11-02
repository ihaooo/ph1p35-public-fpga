`timescale 1ns/1ps
module tb_cam_frame_watchdog;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,armed=0,good_frame_toggle_async=0;
    wire fault;
    wire [7:0] fault_count;
    // 1kHz test clock, 10ms threshold => 10 cycles; production is 24MHz /100ms.
    cam_frame_watchdog #(.CLOCK_HZ(1000),.TIMEOUT_MS(10)) dut (
        .clk(clk),.rst_n(rst_n),.armed(armed),
        .good_frame_toggle_async(good_frame_toggle_async),
        .fault(fault),.fault_count(fault_count)
    );
    initial begin
        repeat(4) @(negedge clk); rst_n=1;
        repeat(20) @(negedge clk);
        if (fault || fault_count) $fatal(1,"fault before initialization");
        armed=1;
        repeat(12) @(negedge clk);
        if (!fault || fault_count!==8'd1) $fatal(1,"first 10ms fault");
        repeat(20) @(negedge clk);
        if (fault_count!==8'd1) $fatal(1,"must count once per outage");
        good_frame_toggle_async=~good_frame_toggle_async;
        repeat(4) @(negedge clk);
        if (fault) $fatal(1,"missing spontaneous clear");
        repeat(12) @(negedge clk);
        if (!fault || fault_count!==8'd2) $fatal(1,"second 10ms fault");
        $display("PASS cam_frame_watchdog"); $finish;
    end
endmodule
