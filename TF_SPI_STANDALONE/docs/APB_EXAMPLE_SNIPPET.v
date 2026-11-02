// Example of the APB slave hookup only; place inside the *verified* MCU SoC top.
// Do NOT set fake MCU clock or memory-map addresses. Consult official PH1P35
// MCU IP / FD BSP for paddr decode, pclk and reset polarity.
// The MCU APB master port exposes paddr[19:0],psel,penable,pwrite,pwdata,
// prdata,pready,pslverr; the MCU HREADY/HRDATA AHB port also needs a
// proper memory/bridge attachment separately.
//
// sd_spi_apb u_tf_spi(
//   .pclk(apb_clk_approved),.presetn(apb_reset_n_approved),
//   .paddr(mcu_paddr),.psel(mcu_psel_tf),.penable(mcu_penable),
//   .pwrite(mcu_pwrite),.pwdata(mcu_pwdata),
//   .prdata(tf_prdata),.pready(tf_pready),.pslverr(tf_pslverr),
//   .sd_cs_n(SD_DAT3),.sd_sclk(SD_CLK),.sd_mosi(SD_CMD),
//   .sd_miso(SD_DAT0)
// );
