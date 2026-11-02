# HX1P35A / PH1P35MDG324: TF 卡独立上板探测工程

状态：**源文件及 TD 项目已准备；未在 TD 6.2/真实 HX1P35A 上编译与烧录。**

这是独立的、很小的验证工程，临时取代视频工程位流，仅验证物理引脚和 SD SPI CMD0 握手。**不读文件、不运行 MCU/AI。**

## 工程与引脚

打开 `td_project/tf_probe.al`，顶层 `tf_probe_top`，器件 `PH1P35MDG324`、速度等级 `-3`。输入 50MHz `C4`，复位 KEY1 `D5`（按下为低）。

- TF 卡背面插槽：`SD_CLK A7`、`SD_CMD/MOSI A8`、`SD_DAT3/CS B12`、`SD_DAT0/MISO E8`。
- LED1 `D10`：CMD0 响应为 `0x01`；LED2 `E10`：CMD0 未通过；LED3 `C6`：系统心跳；LED4 `D6`：探测期间亮。
- 依据：用户提供《新HX1P35A开发板手册-HDL版2604.pdf》24页的 TF 引脚表、19-20 页的 LED 引脚表，以及 5-6 页 50MHz 时钟表。

## TD 烧录步骤（先用 JTAG，别先烧写 FLASH）

1. 插好 TF 卡并断电，再接 USB-JTAG 和供电，打开板上电源。
2. 在 TD 6.2 打开 `tf_probe.al`，检查 `TOP_MODULE = tf_probe_top` 以及 `tf_probe.adc` 约束，**不要打开原来的 camera_to_dsi_display.al**。
3. 依次运行综合、布局布线、生成 Bitstream；确认无 error、Timing WNS >= 0、器件型号正确，再继续。
4. 进入 TD 的 `Download` / `BitWriter`，刷新识别芯片，选择刚生成的 `tf_probe*.bit`（以你电脑上的实际输出为准）。
5. 选择 `JTAG`，点击 `Run`，首次优先以相对较低的 JTAG 频率下载。此模式只是 SRAM 配置，断电失效。
6. LED3 应有心跳。LED1亮 = CMD0握手响应正确。LED2亮 = 握手失败（卡、引脚、电源、接触、时钟或卡初始化问题）。LED1亮**不表示**已经读取 FAT32 或模型文件。
7. 如需要上电保留，等验证通过后，确认连接的配置 Flash 型号与当前 TD 下载模式，再考虑 `PROGRAM FLASH`。**先保存原来的可用位流并确保可恢复**。

## 已知限定

- 这是 SD SPI CMD0 物理/协议冒烟测试。部分 TF 卡可能因为上电延时、信号上拉、兼容性不同造成误判；失败需用逻辑分析仪或 TangAnalyzer 排查。
- `tf_probe.al` 是参照原工程 TD 6.2 的工程字段生成的，还没有在现场 TD GUI 做导入验证。若 TD 无法解析，建议在 TD 创建同器件新工程、添加两个 `.v` 与 `.adc/.sdc` 文件并指定 `tf_probe_top`。
- `sd_spi_apb.v` 可在后续 TD+FD MCU 设计中实例化；**独立探测工程没有把 APB 连接到 MCU**。
- 绝对不要把 `model_int8.bin` 添加到 TD Download 的位流文件栏。
