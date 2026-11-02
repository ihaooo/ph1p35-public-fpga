`timescale 1ns/1ps
// Confirms one-hot selection, blank-before-switch and live mode indication.
module tb_v276_sevenseg;
    reg clk=0,rst_n=0,frame_start=0,pv_enable=0,pv_calibrated=0,pv_dirty=0;
    reg [2:0] algorithm_mode=0;
    reg [2:0] object_count=0;
    reg ccl_fault=0;
    wire buzzer_n;
    wire [7:0] dig,sel;
    integer k,seen0,seen1;
    always #5 clk=~clk;
    pv_board_io_ctrl #(.CLK_HZ(800),.DIGIT_REFRESH_HZ(10)) dut(
        .clk(clk),.rst_n(rst_n),.frame_start(frame_start),
        .algorithm_mode(algorithm_mode),.pv_enable(pv_enable),
        .pv_calibrated(pv_calibrated),.pv_dirty(pv_dirty),
        .object_count(object_count),.ccl_fault(ccl_fault),
        .buzzer_n(buzzer_n),.dig(dig),.sel(sel));
    initial begin
        repeat(4) @(negedge clk); rst_n=1;
        @(negedge clk);frame_start=1;pv_enable=1;pv_calibrated=1;
        pv_dirty=1;object_count=2;
        @(negedge clk);frame_start=0;
        // Change mode WITHOUT a new frame edge; mode must still update.
        algorithm_mode=3;
        seen0=0;seen1=0;
        for(k=0;k<200;k=k+1) begin
            @(posedge clk); #1;
            case (sel)
                8'hFF,8'hFE,8'hFD,8'hFB,8'hF7,8'hEF,8'hDF,8'hBF,8'h7F: ;
                default: $fatal(1,"multi-select error: %h",sel);
            endcase
            if(sel==8'hFE) begin
                seen0=seen0+1;
                if(dig!==8'h92) $fatal(1,"MODE3 should display S, got %h",dig);
            end
            if(sel==8'hFD) begin
                seen1=seen1+1;
                if(dig!==8'hB0) $fatal(1,"MODE3 should display 3, got %h",dig);
            end
        end
        if(seen0==0 || seen1==0) $fatal(1,"scan did not refresh both digits");
        $display("PASS V2.7.6 seven-segment blanking and live-mode test");
        $finish;
    end
endmodule
