`timescale 1ns/1ps
module tb_v282_auto_exposure;
  reg clk=0, rst_n=0, enable=1, stats_enable=1;
  reg frame_start=0, line_end=0, de=0;
  reg [23:0] pixel_in=24'd0;
  wire [23:0] pixel_out;
  wire [7:0] frame_stat_y;
  wire frame_stat_toggle;
  integer x,y;
  reg toggle_before;
  always #5 clk=~clk;

  auto_exposure dut(
    .clk(clk),.rst_n(rst_n),.enable(enable),.stats_enable(stats_enable),
    .frame_start(frame_start),.line_end(line_end),.de(de),.pixel_in(pixel_in),
    .pixel_out(pixel_out),.frame_stat_y(frame_stat_y),
    .frame_stat_toggle(frame_stat_toggle)
  );

  task send_frame;
    input [7:0] gray;
    begin
      // SOF coincides with the first active pixel (0,0).
      @(negedge clk); frame_start=1; de=1; line_end=0;
      pixel_in={gray,gray,gray};
      @(negedge clk); frame_start=0;
      for (y=0;y<720;y=y+1) begin
        for (x=1;x<1280;x=x+1) begin
          de=1; line_end=(x==1279); pixel_in={gray,gray,gray};
          @(negedge clk);
        end
        de=0; line_end=0;
        repeat(4) @(negedge clk);
        if (y<719) begin
          // First pixel of the next row; following loop begins at x=1.
          de=1; pixel_in={gray,gray,gray};
          @(negedge clk);
        end
      end
      de=0; line_end=0;
    end
  endtask

  initial begin
    repeat(4) @(negedge clk); rst_n=1;
    toggle_before=frame_stat_toggle;
    send_frame(8'd128);
    send_frame(8'd128); // SOF of this frame publishes the previous frame.
    if (frame_stat_toggle == toggle_before) $fatal(1,"no complete-frame statistic published");
    if (frame_stat_y != 8'd128) $fatal(1,"expected Yavg=128, got %0d",frame_stat_y);
    $display("PASS tb_v282_auto_exposure: 4x4 sample average and frame validation");
    $finish;
  end
endmodule
