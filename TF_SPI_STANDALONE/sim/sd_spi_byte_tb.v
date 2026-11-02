`timescale 1ns/1ps
module sd_spi_byte_tb;
  reg clk=0, rst_n=0, start=0;
  reg [7:0] tx_data=8'h00;
  wire [7:0] rx_data;
  wire busy,done,sclk,mosi;
  wire miso=mosi; // digital loopback: RX must exactly match TX
  always #10 clk=~clk; // 50 MHz
  sd_spi_byte dut(.clk(clk),.rst_n(rst_n),.start(start),
    .divider(16'd2),.tx_data(tx_data),.rx_data(rx_data),
    .busy(busy),.done(done),.sclk(sclk),.mosi(mosi),.miso(miso));
  initial begin
    repeat(5) @(negedge clk); rst_n=1;
    @(negedge clk); tx_data=8'ha5;start=1;
    @(negedge clk); start=0;
    wait(done);
    #1;
    if(rx_data!==8'ha5) begin $display("FAIL RX 0x%02x",rx_data);$finish;end
    @(negedge clk);tx_data=8'h3c;start=1;
    @(negedge clk);start=0;
    wait(done);
    #1;
    if(rx_data!==8'h3c) begin $display("FAIL RX 0x%02x",rx_data);$finish;end
    $display("PASS sd_spi_byte loopback A5/3C");$finish;
  end
  initial begin #100000; $display("FAIL timeout"); $finish;end
endmodule
