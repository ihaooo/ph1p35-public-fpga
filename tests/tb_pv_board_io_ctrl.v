// Current-version board I/O regression test. Legacy v276-v278 testbenches
// target their historical versions and are not the V2.8.6 reference.
`timescale 1ns/1ps
module tb_pv_board_io_ctrl;
  reg clk=0, rst_n=0, frame_start=0;
  reg [2:0] algorithm_mode=3'd0;
  reg pv_enable=1, pv_calibrated=1, pv_dirty=0, ccl_fault=0;
  reg [2:0] object_count=0;
  wire buzzer_n, servo_alarm;
  wire [7:0] dig,sel;
  always #5 clk=~clk;
  // Accelerated clock and envelope for functional tests only.
  pv_board_io_ctrl #(
    .CLK_HZ(8000),.DIGIT_REFRESH_HZ(100),
    .SIREN_SHORT_ON_MS(3),.SIREN_SHORT_OFF_MS(2),
    .SIREN_LONG_ON_MS(4),.SIREN_REST_MS(5),
    .DIRTY_CONFIRM_FRAMES(3),.CLEAN_CONFIRM_FRAMES(6),
    .PASSIVE_TONE_ENABLE(0)
  ) dut (
    .clk(clk),.rst_n(rst_n),.frame_start(frame_start),
    .algorithm_mode(algorithm_mode),.pv_enable(pv_enable),
    .pv_calibrated(pv_calibrated),.pv_dirty(pv_dirty),
    .object_count(object_count),.ccl_fault(ccl_fault),
    .buzzer_n(buzzer_n),.servo_alarm(servo_alarm),.dig(dig),.sel(sel));
  task frame;
    begin
      @(negedge clk);frame_start=1;
      @(negedge clk);frame_start=0;
    end
  endtask
  integer i, seen_mask;
  initial begin
    repeat(4) @(negedge clk);rst_n=1;
    pv_dirty=1;
    frame;frame;
    if(servo_alarm!==0 || buzzer_n!==1) $fatal(1,"alarm before 3 valid frames");
    frame;
    #1;
    if(servo_alarm!==1 || buzzer_n!==0) $fatal(1,"alarm should activate after 3 frames");
    seen_mask=0;
    for(i=0;i<270;i=i+1) begin
      @(negedge clk);
      case (sel)
        8'hFF,8'hFE,8'hFD,8'hFB,8'hF7,8'hEF,8'hDF,8'hBF,8'h7F: ;
        default: $fatal(1,"scan select is not one-hot or blank: %h",sel);
      endcase
      if (dut.siren_phase<=5) seen_mask=seen_mask | (1<<dut.siren_phase);
      if ((dut.siren_phase==1 || dut.siren_phase==3 || dut.siren_phase==5) && buzzer_n!==1)
        $fatal(1,"siren gap is not silent");
    end
    if((seen_mask & 6'b111111)!==6'b111111) $fatal(1,"missing siren phases");
    pv_dirty=0;
    repeat(5) frame;
    if(servo_alarm!==1) $fatal(1,"release too early");
    frame;
    #1;
    if(servo_alarm!==0 || buzzer_n!==1) $fatal(1,"release should occur at frame 6");
    pv_dirty=1;
    repeat(3) frame;
    if(servo_alarm!==1) $fatal(1,"second alert missing");
    ccl_fault=1;
    #1;
    if(servo_alarm!==0 || buzzer_n!==1) $fatal(1,"CAM_ERR must immediately suppress alarm");
    $display("PASS: siren pattern + dirty confirm/release + fault safe + scan");
    $finish;
  end
endmodule
