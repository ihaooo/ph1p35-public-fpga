# 公开 RTL

本目录只保留可独立发布的基础模块。

| 目录 | 内容 |
|---|---|
| `common/` | 视频流接口定义 |
| `isp/` | AE、AWB、直方图与基础像素处理 |
| `overlay/` | 状态叠加与显示亮度 |
| `control/` | 按键、拨码、模式、报警与舵机 PWM |
| `perf/` | 帧编号和跨时钟域快照 |
| `diagnostics/` | 摄像头帧看门狗 |
| `tf_card/` | TF/SPI APB 和字节接口 |

未包含：

- `algorithm/`：污渍检测核心；
- `app/`：完整私有顶层和集成逻辑；
- MCU 生成的 IP；
- 官方/第三方厂商 IP。

使用前请按自己的器件和板卡重新确认依赖、时序、复位极性和引脚约束。公开模块采用 Verilog-2001/SystemVerilog 可综合子集，ModelSim 测试使用 `vlog -sv`。

