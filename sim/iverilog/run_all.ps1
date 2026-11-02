$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $root

$rtl = @(
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
    "rtl/tf_card/tf_probe_top.v"
)

$tests = @(
    @("tb_mode_ctrl_ae", "sim/tb_mode_ctrl_ae.v"),
    @("tb_key_event_reserve", "sim/tb_key_event_reserve.v"),
    @("tb_v282_auto_exposure", "tests/tb_v282_auto_exposure.v"),
    @("tb_v283_awb_gray_blocks", "tests/tb_v283_awb_gray_blocks.v"),
    @("tb_frame_id_rollover", "sim/tb_frame_id_rollover.v"),
    @("tb_frame_id_tagging", "sim/tb_frame_id_tagging.v"),
    @("tb_cam_frame_watchdog", "tests/tb_cam_frame_watchdog.v"),
    @("tb_pv_board_io_ctrl", "tests/tb_pv_board_io_ctrl.v"),
    @("tb_v277_sevenseg", "tests/tb_v277_sevenseg.v"),
    @("tb_v276_sevenseg", "tests/tb_v276_sevenseg.v"),
    @("tb_v286_siren", "tests/tb_v286_siren.v"),
    @("sd_spi_byte_tb", "TF_SPI_STANDALONE/sim/sd_spi_byte_tb.v")
)

if (-not (Get-Command iverilog -ErrorAction SilentlyContinue)) {
    throw "iverilog is not in PATH."
}
if (-not (Get-Command vvp -ErrorAction SilentlyContinue)) {
    throw "vvp is not in PATH."
}

New-Item -ItemType Directory -Path "build_iverilog" -Force | Out-Null

foreach ($test in $tests) {
    $name = $test[0]
    $tb = $test[1]
    Write-Host "`n=== $name ===" -ForegroundColor Cyan
    iverilog -g2012 -s $name -I rtl/common `
        -o "build_iverilog/$name.vvp" @rtl $tb
    if ($LASTEXITCODE -ne 0) { throw "$name compile failed" }

    vvp "build_iverilog/$name.vvp"
    if ($LASTEXITCODE -ne 0) { throw "$name failed" }
}

Write-Host "`nAll 12 Icarus Verilog tests passed." -ForegroundColor Green

