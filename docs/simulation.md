# ModelSim 仿真

## 环境与验证结果

本次发布使用以下环境：

```text
ModelSim 10.6d
Icarus Verilog 13
Windows x64
```

| 检查 | 结果 |
|---|---|
| ModelSim `vlog -sv` 编译 | 通过，0 error / 0 warning |
| ModelSim `vsim` 运行 | 本机许可证环境不可用，未执行 |
| Icarus Verilog 12 项运行 | 全部通过 |

需要的命令：

```text
vlib
vmap
vlog
vsim
```

如果这些命令不在 `PATH` 中，请先把 ModelSim 的 `win64` 目录加入当前终端环境。

## 一键运行

PowerShell：

```powershell
cd sim\modelsim
.\run_all.ps1
```

批处理：

```bat
cd sim\modelsim
run_all.bat
```

在已正确配置 ModelSim 许可证的机器上，脚本会：

1. 建立并映射 `work` 库；
2. 以 SystemVerilog 模式编译公开 RTL 和测试平台；
3. 依次运行所有自检测试；
4. 任一测试返回非零状态时立即失败。

如果本机暂时没有 ModelSim 许可证，可以使用同等的 Icarus Verilog 测试入口：

```powershell
cd sim\iverilog
.\run_all.ps1
```

## 当前测试

| 测试 | 验证内容 |
|---|---|
| `tb_mode_ctrl_ae` | K1/K2 模式切换、保留键不触发短按动作 |
| `tb_key_event_reserve` | 长按、组合键隔离和保留事件 |
| `tb_v282_auto_exposure` | AE 帧统计与连续输出 |
| `tb_v283_awb_gray_blocks` | 灰块样本、过曝/黑场排除与增益更新 |
| `tb_frame_id_rollover` | 帧编号回绕与陈旧帧失效 |
| `tb_frame_id_tagging` | DDR/HDMI 跨时钟域一致快照 |
| `tb_cam_frame_watchdog` | 摄像头帧超时检测 |
| `tb_pv_board_io_ctrl` | 板级 I/O 控制 |
| `tb_v277_sevenseg` | 数码管动态扫描和消隐 |
| `tb_v276_sevenseg` | 数码管位选与模式显示 |
| `tb_v286_siren` | 报警确认、释放和故障安全 |
| `sd_spi_byte_tb` | TF/SPI 单字节发送接收 |

## 单测示例

```powershell
cd sim\modelsim
vlib work
vmap work work
vlog -sv +incdir+../../rtl/common `
  ../../rtl/control/mode_ctrl.v `
  ../../sim/tb_mode_ctrl_ae.v
vsim -c -do "run -all; quit -f" work.tb_mode_ctrl_ae
```

## 输出

成功测试会打印类似：

```text
PASS: KEY2/KEY3 mode, KEY4 short no AE action
```

`$fatal` 会以非零状态结束仿真。CI 或其他自动化流程应根据 `vsim` 返回码判断是否通过。

## 不包含的测试

以下测试依赖未公开核心，暂不进入公开仿真：

- 污渍检测、连通域和目标定位；
- 形态分类和风险优先级；
- MCU 模型读取与 INT8 推理；
- 私有顶层集成和完整位流回归。

