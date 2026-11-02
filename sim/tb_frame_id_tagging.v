`timescale 1ns/1ps
// Pure behavioral test: DDR slot association, startup, repeated display,
// camera advances, conflict, and DDR-to-HDMI snapshot coherence.
// Run: iverilog -g2005 -s tb_frame_id_tagging -o /tmp/tag.vvp \
//   rtl/perf/frame_id_tracker.v rtl/perf/frame_id_snapshot_cdc.v \
//   sim/tb_frame_id_tagging.v && vvp /tmp/tag.vvp
module tb_frame_id_tagging;
    reg ddr_clk=0, hdmi_clk=0, rst_n=0;
    always #5 ddr_clk=~ddr_clk;
    always #7 hdmi_clk=~hdmi_clk;
    reg cap=0, disp=0;
    reg [1:0] cap_slot=0, disp_slot=0;
    wire [15:0] src_cap,src_disp;
    wire [11:0] src_lag;
    wire src_valid,src_toggle;
    wire [15:0] dst_cap,dst_disp;
    wire [11:0] dst_lag;
    wire dst_valid,dst_update;
    integer errors=0;

    frame_id_tracker dut (
        .clk(ddr_clk),.rst_n(rst_n),
        .capture_start(cap),.capture_slot(cap_slot),
        .display_start(disp),.display_slot(disp_slot),
        .snapshot_capture_id(src_cap),.snapshot_display_id(src_disp),
        .snapshot_lag_frames(src_lag),.snapshot_valid(src_valid),
        .snapshot_toggle(src_toggle)
    );
    frame_id_snapshot_cdc dut_cdc (
        .clk(hdmi_clk),.rst_n(rst_n),
        .src_capture_id(src_cap),.src_display_id(src_disp),
        .src_lag_frames(src_lag),.src_valid(src_valid),
        .src_toggle(src_toggle),
        .capture_id(dst_cap),.display_id(dst_disp),
        .lag_frames(dst_lag),.valid(dst_valid),.update_pulse(dst_update)
    );
    task capture_frame;
        input [1:0] slot;
        begin
            @(negedge ddr_clk); cap_slot=slot; cap=1;
            @(negedge ddr_clk); cap=0;
        end
    endtask
    task display_frame;
        input [1:0] slot;
        begin
            @(negedge ddr_clk); disp_slot=slot; disp=1;
            @(negedge ddr_clk); disp=0;
            repeat(7) @(posedge hdmi_clk);
            #1;
        end
    endtask
    task expect_snapshot;
        input [15:0] exp_cap,exp_disp;
        input [11:0] exp_lag;
        input exp_valid;
        begin
            if(src_cap!==exp_cap || src_disp!==exp_disp ||
               src_lag!==exp_lag || src_valid!==exp_valid ||
               dst_cap!==exp_cap || dst_disp!==exp_disp ||
               dst_lag!==exp_lag || dst_valid!==exp_valid) begin
                $display("ERROR cap=%h/%h disp=%h/%h lag=%h/%h valid=%b/%b expected %h %h %h %b",
                        src_cap,dst_cap,src_disp,dst_disp,src_lag,dst_lag,
                        src_valid,dst_valid,exp_cap,exp_disp,exp_lag,exp_valid);
                errors=errors+1;
            end
        end
    endtask
    initial begin
        repeat(4) @(negedge ddr_clk); rst_n=1;
        // Startup: output buffer never written => TAG WAIT, LAG ---F.
        display_frame(2); expect_snapshot(16'd0,16'd0,12'd0,1'b0);
        capture_frame(0); // #1 into slot0
        capture_frame(1); // #2 into slot1
        capture_frame(2); // #3 into slot2
        display_frame(0); expect_snapshot(16'd3,16'd1,12'd2,1'b1);
        // Source stalls but HDMI displays same frame: ID remains stable.
        display_frame(0); expect_snapshot(16'd3,16'd1,12'd2,1'b1);
        capture_frame(3); // #4 into slot3
        display_frame(1); expect_snapshot(16'd4,16'd2,12'd2,1'b1);
        // Same edge attempts reading a slot that is being overwritten.
        @(negedge ddr_clk); cap=1; disp=1; cap_slot=1; disp_slot=1;
        @(negedge ddr_clk); cap=0; disp=0;
        repeat(7) @(posedge hdmi_clk); #1;
        expect_snapshot(16'd5,16'd2,12'd0,1'b0);
        display_frame(1); expect_snapshot(16'd5,16'd5,12'd0,1'b1);
        if(errors) begin
            $display("FAIL tb_frame_id_tagging errors=%0d",errors); $fatal(1);
        end
        $display("PASS tb_frame_id_tagging: DDR slots + coherent CDC");
        $finish;
    end
endmodule
