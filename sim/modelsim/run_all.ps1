$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $root

$sources = @(
    "rtl/common/video_stream_if.vh",
    "rtl/isp/auto_exposure.v",
    "rtl/isp/auto_white_balance.v",
    "rtl/isp/histogram_equalizer.v",
    "rtl/isp/pixel_algorithm.v",
    "rtl/overlay/adaptive_brightness.v",
    "rtl/overlay/status_overlay.v",
    "rtl/control/mode_ctrl.v",
    "rtl/control/switch_ctrl.v",
    "rtl/control/pv_servo_pwm.v",
    "rtl/control/pv_board_io_ctrl.v",
    "rtl/perf/frame_id_tracker.v",
    "rtl/perf/frame_id_snapshot_cdc.v",
    "rtl/diagnostics/cam_frame_watchdog.v",
    "rtl/tf_card/sd_spi_byte.v",
    "rtl/tf_card/sd_spi_apb.v",
    "rtl/tf_card/tf_probe_top.v",
    "sim/tb_frame_id_rollover.v",
    "sim/tb_frame_id_tagging.v",
    "sim/tb_key_event_reserve.v",
    "sim/tb_mode_ctrl_ae.v",
    "tests/tb_cam_frame_watchdog.v",
    "tests/tb_v282_auto_exposure.v",
    "tests/tb_v283_awb_gray_blocks.v",
    "tests/tb_v276_sevenseg.v",
    "tests/tb_v277_sevenseg.v",
    "tests/tb_v286_siren.v",
    "tests/tb_pv_board_io_ctrl.v",
    "TF_SPI_STANDALONE/sim/sd_spi_byte_tb.v"
)

$tests = @(
    "tb_mode_ctrl_ae",
    "tb_key_event_reserve",
    "tb_v282_auto_exposure",
    "tb_v283_awb_gray_blocks",
    "tb_frame_id_rollover",
    "tb_frame_id_tagging",
    "tb_cam_frame_watchdog",
    "tb_pv_board_io_ctrl",
    "tb_v277_sevenseg",
    "tb_v276_sevenseg",
    "tb_v286_siren",
    "sd_spi_byte_tb"
)

if (-not (Get-Command vlib -ErrorAction SilentlyContinue)) {
    throw "ModelSim tools are not in PATH. Add the ModelSim win64 directory to PATH."
}

Remove-Item -Recurse -Force -LiteralPath "work" -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath "modelsim.ini" -ErrorAction SilentlyContinue

vlib work
if ($LASTEXITCODE -ne 0) { throw "vlib failed" }
vmap work work
if ($LASTEXITCODE -ne 0) { throw "vmap failed" }

vlog -sv +incdir+rtl/common @sources
if ($LASTEXITCODE -ne 0) { throw "vlog failed" }

foreach ($test in $tests) {
    Write-Host "`n=== $test ===" -ForegroundColor Cyan
    vsim -c -do "run -all; quit -f" "work.$test"
    if ($LASTEXITCODE -ne 0) { throw "$test failed" }
}

Write-Host "`nAll public ModelSim tests passed." -ForegroundColor Green

