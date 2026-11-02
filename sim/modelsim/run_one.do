# Usage from the repository root:
#   vsim -c -do "do sim/modelsim/run_one.do work.tb_mode_ctrl_ae"
#
# This helper compiles the public sources and runs one test bench.
set root [file normalize [file dirname [info script]]/../..]
cd $root

vlib work
vmap work work
vlog -sv +incdir+rtl/common \
  rtl/isp/auto_exposure.v \
  rtl/isp/auto_white_balance.v \
  rtl/isp/histogram_equalizer.v \
  rtl/isp/pixel_algorithm.v \
  rtl/overlay/adaptive_brightness.v \
  rtl/overlay/status_overlay.v \
  rtl/control/mode_ctrl.v \
  rtl/control/switch_ctrl.v \
  rtl/control/pv_servo_pwm.v \
  rtl/control/pv_board_io_ctrl.v \
  rtl/perf/frame_id_tracker.v \
  rtl/perf/frame_id_snapshot_cdc.v \
  rtl/diagnostics/cam_frame_watchdog.v \
  rtl/tf_card/sd_spi_byte.v \
  rtl/tf_card/sd_spi_apb.v \
  rtl/tf_card/tf_probe_top.v \
  sim/tb_frame_id_rollover.v \
  sim/tb_frame_id_tagging.v \
  sim/tb_key_event_reserve.v \
  sim/tb_mode_ctrl_ae.v \
  tests/tb_cam_frame_watchdog.v \
  tests/tb_v282_auto_exposure.v \
  tests/tb_v283_awb_gray_blocks.v \
  tests/tb_v276_sevenseg.v \
  tests/tb_v277_sevenseg.v \
  tests/tb_v286_siren.v \
  tests/tb_pv_board_io_ctrl.v \
  TF_SPI_STANDALONE/sim/sd_spi_byte_tb.v

vsim -c -do "run -all; quit -f" [lindex $argv 0]

