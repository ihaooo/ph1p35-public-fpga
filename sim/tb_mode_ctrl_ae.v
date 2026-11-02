`timescale 1ns/1ps
// Run after adding an HDL simulator, e.g.:
//   iverilog -g2012 -s tb_mode_ctrl_ae -o sim.out \
//     rtl/control/mode_ctrl.v sim/tb_mode_ctrl_ae.v
//   vvp sim.out
module tb_mode_ctrl_ae;
    reg clk=1'b0;
    always #5 clk=~clk;
    reg rst_n=1'b0;
    reg [2:0] buttons_n=3'b111;
    wire [2:0] mode;
    wire ae_gate;
    algorithm_mode_ctrl #(.DEBOUNCE_CYCLES(3)) dut(
        .clk(clk),.rst_n(rst_n),.buttons_n(buttons_n),
        .mode(mode),.ae_gate(ae_gate)
    );
    task press_key;
        input integer index;
        begin
            @(negedge clk); buttons_n[index]=1'b0;
            repeat(14) @(negedge clk);
            buttons_n[index]=1'b1;
            repeat(14) @(negedge clk);
        end
    endtask
    task expect_state;
        input [2:0] m;
        input expected_gate;
        begin
            if (mode!==m || ae_gate!==expected_gate) begin
                $display("FAIL mode=%d expected=%d AE=%b expected=%b",
                         mode,m,ae_gate,expected_gate);
                $fatal(1);
            end
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);
        rst_n=1'b1;
        repeat(4) @(negedge clk);
        expect_state(3'd0,1'b1);
        press_key(0);expect_state(3'd1,1'b1);
        press_key(0);expect_state(3'd2,1'b1);
        press_key(0);expect_state(3'd3,1'b1);
        press_key(0);expect_state(3'd0,1'b1);
        press_key(1);expect_state(3'd4,1'b1);
        press_key(1);expect_state(3'd5,1'b1);
        press_key(1);expect_state(3'd0,1'b1);
        // Short K4 must neither change AE nor algorithm mode.
        press_key(2);expect_state(3'd0,1'b1);
        press_key(2);expect_state(3'd0,1'b1);
        $display("PASS: KEY2/KEY3 mode cycle, KEY4 short no AE action");
        $finish;
    end
endmodule
