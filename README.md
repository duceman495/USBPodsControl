# USBPodsControl

一款用于控制 [wasdwasd0105/USBPods-Pico2W](https://github.com/wasdwasd0105/USBPods-Pico2W)（**Lite 开源固件**）的原生 macOS 图形化控制面板与菜单栏应用。

无需修改固件源码，插上刷好 `USBPods_Pico2W_Lite.uf2` 的 **Waveshare RP2350B-Plus-W** 或 **Raspberry Pi Pico 2 W**，即可在 Mac 上通过图形界面完成蓝牙耳机配对、双槽位切换、LDAC / LHDC 实时码率调节、编码开关与系统声音输出一键切换。

> Native macOS SwiftUI & Menu Bar companion app for `wasdwasd0105/USBPods-Pico2W` (`USBPods Lite` firmware, V1.0.2+). Zero third-party dependencies, zero firmware changes required.

---

## 支持硬件 / Supported Hardware

- **Waveshare RP2350B-Plus-W**（Type-C 接口，推荐）
- **Raspberry Pi Pico 2 W**
- 固件：[`wasdwasd0105/USBPods-Pico2W`](https://github.com/wasdwasd0105/USBPods-Pico2W/releases)（`USBPods_Pico2W_Lite.uf2` V1.0.2+）

---

## 核心功能 / Features

- **即插即用与自动重连**：基于 `IOKit` 自动识别 `VID=0xCAFE` / `USBPods Lite` USB CDC 串口，支持热拔插自动恢复连接。
- **Mac 音频输出一键切换**：通过 `CoreAudio` 实时检测默认输出设备，未指向 `USBPods` 时可一键切换。
- **耳机配对与双槽位切换**：
  - 直观显示当前连接耳机、播放状态、协商编码、实时码率及电量（HFP / 左右耳 / 充电盒）。
  - 一键回连、断开、在指定槽位（Slot 1 / Slot 2）扫描配对新耳机或切换槽位。
- **编码与实时码率控制**：
  - **LDAC**：`330 / 660 / 990 kbps` 不断连实时切换。
  - **LHDC V5**：`256 / 400 / 500 / 900 kbps` 不断连实时切换。
  - 独立开关 `LDAC` / `LHDC V5` / `AAC-ELD (AirPods)` / `AAC`，并提供「仅开 LDAC」「全部开启」一键预设及快捷重连按钮。
- **系统设置与终端**：
  - 媒体控制（上一曲 / 播放暂停 / 下一曲 / 音量加减）。
  - 通电自动回连、断连自动暂停 Mac、耳机物理按键模式、USB 模式（UAC2 / UAC1）、采样率（48 / 44.1 kHz）、HFP 电量回传、调试日志与配对清除确认。
  - 内置实时串口终端视图，可直接发送单字符或调试指令。
- **菜单栏常驻**：顶部状态栏实时显示当前编码与码率（如 `LDAC 990k`、`配对中`），右键菜单支持快速切槽位和 LDAC 码率。

---

## 环境要求与构建 / Build & Run

- **系统**：macOS 14.0+
- **工具链**：仅需系统自带的 `swiftc`（Xcode Command Line Tools），无需安装完整 Xcode 或任何第三方依赖。

```bash
git clone https://github.com/duceman495/USBPodsControl.git
cd USBPodsControl
chmod +x build.sh
./build.sh
open dist/USBPodsControl.app
```

> 如需自定义输出路径（例如输出到上层目录或 `/Applications`）：
> ```bash
> APP_OUT="/Applications/USBPodsControl.app" ./build.sh
> ```

### 硬件只读自检 / Hardware Self-Test

构建完成后，可执行无破坏性的只读自检验证 `IOKit` 串口发现、`CoreAudio` 输出设备检测以及 `2.5s` 连续串口稳定性：

```bash
./dist/USBPodsControl.app/Contents/MacOS/USBPodsControl --self-test
```

---

## 目录结构 / Project Layout

| 路径 | 说明 |
|---|---|
| `Sources/Models.swift` | 状态模型、设置枚举、串口与音频状态定义 |
| `Sources/USBDeviceDiscovery.swift` | 基于 `IOKit` 的 USB CDC 串口自动发现 |
| `Sources/CoreAudioHelper.swift` | 基于 `CoreAudio` 的默认音频输出检测与切换 |
| `Sources/SerialPort.swift` | 非阻塞 POSIX 串口驱动与断线检测 |
| `Sources/USBPodsParser.swift` | `USBPods Lite` 菜单、高级菜单与实时事件解析器 |
| `Sources/USBPodsController.swift` | 串行化异步指令队列、轮询与状态管理 |
| `Sources/ContentView.swift` | SwiftUI 三标签页界面（概览 / 设置 / 终端） |
| `Sources/main.swift` | App 入口、菜单栏状态项与 `--self-test` |
| `Resources/Info.plist` | macOS 应用 Bundle 配置 |
| `Tests/ParserTests.swift` | 协议解析单元测试 |
| `build.sh` | 单元测试、矢量图标生成、编译与签名脚本 |

---

## 致谢与协议 / Acknowledgments & License

- 固件与串口协议来自开源项目：[wasdwasd0105/USBPods-Pico2W](https://github.com/wasdwasd0105/USBPods-Pico2W)（GPL-3.0-only with exception）
- 本控制端源码采用 [MIT License](LICENSE) 开源。
