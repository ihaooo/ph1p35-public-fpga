`timescale 1ns/1ps
// Run with Icarus Verilog (when installed):
//   iverilog -g2012 -s tb_v283_awb_gray_blocks -o awb.out \
//     rtl/isp/auto_white_balance.v tests/tb_v283_awb_gray_blocks.v
//   vvp awb.out
module tb_v283_awb_gray_blocks;
  reg clk=0;
  always #5 clk=~clk;
  reg rst_n=0,enable=1,stats_enable=1,frame_start=0,line_end=0,de=0;
  reg [23:0] pixel_in=0;
  wire [23:0] pixel_out;
  auto_white_balance #(
    .IMG_WIDTH(128),.IMG_HEIGHT(128),
    .MIN_CELL_SAMPLES(3),.MIN_GRAY_BLOCKS(8),.UPDATE_EVERY_FRAMES(4)
  ) dut ( .clk(clk),.rst_n(rst_n),.enable(enable),
      .stats_enable(stats_enable),.frame_start(frame_start),
      .line_end(line_end),.de(de),.pixel_in(pixel_in),.pixel_out(pixel_out));
  integer x,y,f,k;
  initial begin
    repeat(8) @(negedge clk); rst_n=1;
    // initialization clears 256 RAM entries
    repeat(300) @(negedge clk);
    if (dut.state != 4'd1) $fatal(1,"RAM clear/initialization failed");
    for(f=0;f<4;f=f+1) begin
      for(y=0;y<128;y=y+1) begin
        for(x=0;x<128;x=x+1) begin
          @(negedge clk);
          frame_start=(x==0 && y==0);
          line_end=(x==127);
          de=1;
          // Neutral-looking warm/cool scene: G > R and G < B.
          pixel_in={8'd100,8'd115,8'd120};
        end
      end
      @(negedge clk);de=0;line_end=0;frame_start=0;
      repeat(1200) @(negedge clk); // simulated vertical blank, scan RAM/divide
      if (dut.state != 4'd1) $fatal(1,"block scan overrun");
    end
    if (dut.gain_r_q8 <= 10'd256) $fatal(1,"R gain failed to increase");
    if (dut.gain_b_q8 >= 10'd256) $fatal(1,"B gain failed to decrease");
    if (dut.gain_r_q8 > 10'd512 || dut.gain_b_q8 < 10'd128)
        $fatal(1,"Q8 gain saturation failed");
    $display("PASS V2.8.3 AWB R=%0d B=%0d",dut.gain_r_q8,dut.gain_b_q8);
    $finish;
  end
endmodule
