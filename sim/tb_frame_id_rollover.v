`timescale 1ns/1ps
// Small modulo counter exercises wrap and stale-gap invalidation quickly.
module tb_frame_id_rollover;
    reg clk=0, rst_n=0, cap=0, disp=0;
    reg [1:0] cap_slot=0, disp_slot=0;
    wire [3:0] cap_id,disp_id;
    wire [2:0] lag;
    wire valid,toggle;
    integer k,errors=0;
    always #5 clk=~clk;
    frame_id_tracker #(.ID_WIDTH(4),.LAG_WIDTH(3)) dut(
        .clk(clk),.rst_n(rst_n),.capture_start(cap),.capture_slot(cap_slot),
        .display_start(disp),.display_slot(disp_slot),
        .snapshot_capture_id(cap_id),.snapshot_display_id(disp_id),
        .snapshot_lag_frames(lag),.snapshot_valid(valid),.snapshot_toggle(toggle));
    task capture;
       input [1:0] slot;
       begin @(negedge clk);cap_slot=slot;cap=1;
             @(negedge clk);cap=0;end
    endtask
    task display;
       input [1:0] slot;
       begin @(negedge clk);disp_slot=slot;disp=1;
             @(negedge clk);disp=0;#1;end
    endtask
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        for(k=0;k<15;k=k+1) capture(k%4); // newest ID 15
        display(2); // slot2 ID 15, lag 0
        if(!valid || cap_id!==4'd15 || disp_id!==4'd15 || lag!==0) errors=errors+1;
        capture(3); // ID wraps to 0 (was 15)
        display(2); // 0 - 15 mod16 = 1
        if(!valid || cap_id!==4'd0 || disp_id!==4'd15 || lag!==1) errors=errors+1;
        for(k=0;k<9;k=k+1) capture(0); // ID 9 in slot0; stale slot2
        display(2); // modulo 16 diff = 10, beyond 3-bit lag range (7)
        if(valid || lag!==0) errors=errors+1;
        if(errors) begin $display("FAIL rollover %d",errors);$fatal(1);end
        $display("PASS tb_frame_id_rollover: modulo and stale gap");$finish;
    end
endmodule
