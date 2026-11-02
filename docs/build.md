# TD 编译与上板

## 1. 可独立打开的工程

公开包中唯一提供完整 TD 入口的是 TF/SPI 独立探测工程：

```text
TF_SPI_STANDALONE/td_project/tf_probe.al
```

参数：

```text
Device : PH1P35MDG324
Speed  : -3
Top    : tf_probe_top
```

该工程只验证 TF 卡 CMD0 响应，不读取模型，不运行 MCU 或 AI。

## 2. 工具要求

- 安路 Tang Dynasty TD 6.2；
- PH1P35 器件支持包；
- BitWriter / JTAG 下载环境；
- 与实际板卡版本一致的引脚和电源资料。

## 3. 编译步骤

1. 打开 `tf_probe.al`。
2. 检查器件、速度等级和顶层。
3. 执行 Synthesis。
4. 执行 Physical Design / Place & Route。
5. 检查时序报告无负裕量。
6. 生成 `.bit`，用文件修改时间确认不是旧结果。
7. 优先使用 `PROGRAM SRAM`，不要直接写配置 Flash。

## 4. 引脚

TF 探测工程使用：

```text
50 MHz : C4
SD_CLK : A7
SD_CMD : A8
SD_CS  : B12
SD_DAT0: E8
```

详细说明见 [TF 探测工程说明](../TF_SPI_STANDALONE/docs/HOW_TO_TEST_TD.md)。

## 5. 公开 RTL 的集成

视频处理和板级控制模块没有附带完整顶层。导入自己的 TD 工程时：

1. 按实际板卡重新确认时钟、复位和引脚；
2. 根据目标器件重新分配 IP；
3. 用 `sim/modelsim/run_all.ps1` 先跑模块级仿真；
4. 单独完成综合和时序检查；
5. 不要直接复用未经验证的 `.adc/.sdc` 约束到其他板卡。

公开包中不提供完整系统 `.bit`，也不能从当前公开源码生成包含私有污渍检测核心的位流。

## 6. 常见问题

### 找不到 MCU 或 `MCU_PLL`

这是预期现象。完整 MCU 工程依赖 TD 生成的厂商 IP，不属于本次公开包。

### 找不到污渍检测模块

这是预期现象。核心检测 RTL 在比赛结束后发布。

### TF 探测失败

先检查卡座引脚、供电、卡是否断电插入和 CMD0 响应。TF 探测通过不代表 FAT32、模型读取或 MCU 联调已经通过。

