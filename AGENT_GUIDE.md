# 67元让 Mac 用上 LDAC / LHDC 蓝牙音频 — AI Agent 手把手部署教程

> **致观看视频来到这里的你**：你可以直接把本页面（或仓库地址）发给你的 AI 编程助手（如 Antigravity、Claude Code、Cursor、Codex、Windsurf 等），让它一步步带着你买对板子、刷好固件、把图形化控制面板跑起来。

---

## 给 AI Agent 的执行指南（AI 必读）

如果你是协助用户完成本项目的 **AI Agent**，请严格遵守以下交互准则：

1. **先问进度，不要一次性丢出所有命令**：先向用户确认当前处于哪个阶段：
   - A. 还没买硬件，需要确认购买清单；
   - B. 开发板已到手，需要刷入 `USBPods Lite` 固件；
   - C. 固件已刷好，需要在 Mac 上编译运行 `USBPodsControl` 图形界面；
   - D. 已运行但遇到配对、无声、卡顿等故障，需要排查。
2. **每执行一步都要做校验再进入下一步**：拥有终端权限时，主动帮用户检查 `/Volumes/RP2350`、`/dev/cu.usbmodem*`、`swiftc --version` 与 `--self-test` 输出；没有终端权限时，一次只给一条清晰指令并让用户把输出贴回来。
3. **不要诱导用户走弯路**：
   - **不要**要求用户安装几十 GB 的完整版 Xcode，本项目仅需 Apple Command Line Tools（`xcode-select --install`）。
   - **不要**让用户自己从头编译 `USBPods-Pico2W` 固件源码（需要特定 SDK patch 和 Rust 交叉工具链），直接使用官方 Release 的通用 `.uf2` 文件（`USBPods_Pico2W_Lite.uf2` V1.0.2+）即可同时兼容官方 Pico 2 W 和微雪 RP2350B-Plus-W。
   - **不要**在操作过程中修改用户的系统设置之外的其他仓库文件。

---

## 阶段一：硬件选购与避坑清单

> **AI Agent 检查点**：如果用户还没下单或刚准备买板子，请先核对以下硬件规格，确认无误后再继续。

### 1. 推荐购买清单

| 物品 | 推荐型号 | 参考价格 | 说明 |
| :--- | :--- | :---: | :--- |
| **主控+蓝牙开发板（二选一）** | **微雪 Waveshare `RP2350B-Plus-W`**（首推） | 约 ¥67 | 自带 **USB Type-C** 接口、**16MB Flash**、BOOT+RESET 双按键、树莓派官方 **RM2（CYW43439）无线模组**，尺寸仅 41.4×21 mm，直插或短线接 Mac 最方便。 |
| | 树莓派官方 `Raspberry Pi Pico 2 W` | 约 ¥55–70 | 4MB Flash，官方正版，但接口是 **Micro-USB**（需另配 C 转 Micro-USB 数据线/转接头）。 |
| **USB 数据线** | **支持数据传输的 USB-C 线**（或 C-to-C 短线） | 约 ¥10 | 手机充电线中不少是“仅充电无数据线”，插上电脑没反应几乎都是线的问题。 |
| **耳机** | 任意支持 **LDAC / LHDC / AAC-ELD / AAC** 的蓝牙耳机 | 自备 | 例如索尼 WH/WF-1000XM 系列、小米/OPPO LHDC 耳机、AirPods 等。 |

### 2. 必看硬件避坑（千万别买错！）

- ❌ **不要买 BW16（RTL8720DN）、ESP32-S3 / C3 / C6、BK7258、nRF52/53**：这些芯片只支持低功耗蓝牙（BLE），**没有经典蓝牙（BR/EDR）**，无法运行 A2DP/LDAC。
- ❌ **不要买老款 RP2040（如标着 2MB Flash 的“Pico W 创客版”）**：`USBPods-Pico2W` 固件需要 **RP2350** 算力才能实时跑高码率 LDAC/LHDC，老款 Pico W（RP2040）不支持新版固件。
- ❌ **不要买换了无线芯片的第三方 RP2350 无线板**：市面上部分第三方魔改板虽然用 RP2350，但把无线换成了 ESP32-C3/C6 或 RTL8720DN，刷入固件后无线无法启动。必须确认无线芯片为 **英飞凌 CYW43439** 或 **Raspberry Pi Radio Module 2 (RM2)**。
- ❌ **不要用全金属外壳**：会严重屏蔽 2.4GHz 蓝牙信号，导致 LDAC 990 kbps 断音。如需外壳，请用 3D 打印（PLA/PETG/树脂）或透明热缩管。

---

## 阶段二：下载并刷入开源固件（`USBPods Lite`）

> **原理解释**：macOS 锁死了自带蓝牙栈的编码选择（只放行 SBC/AAC），但对标准 USB 声卡完全免驱。刷入 [`wasdwasd0105/USBPods-Pico2W`](https://github.com/wasdwasd0105/USBPods-Pico2W) 的开源固件后，Mac 只会把开发板识别成一块普通 USB 声卡，由板子完成 LDAC / LHDC 编码并直接无线发给耳机。

### 1. 让板子进入刷机模式（U 盘模式）

引导用户执行以下物理操作：
1. **按住开发板上的 `BOOT`（或 `BOOTSEL`）按键不要松手**；
2. 用**带数据传输功能的 USB-C 线**把板子插到 Mac 上；
3. 等待 1 秒后松开 `BOOT` 键。  
   *(若数据线本来就插着：按住 `BOOT` 不放 → 轻按一下 `RESET` → 松开 `BOOT`)*

### 2. 验证磁盘挂载（AI Agent 可在终端执行）

```bash
ls -la /Volumes
```

确认输出中出现 **`RP2350`** 磁盘目录。如果未出现，请先排查数据线是否支持传输以及按键顺序是否正确。

### 3. 下载最新通用 `.uf2` 固件并刷入

自 `V1.0.2` 起，官方 Release 中的 `USBPods_Pico2W_Lite.uf2` 已是**二合一通用固件**，开机自动探测微雪（GPIO 36–39）与官方 Pico 2 W（GPIO 23–25/29）无线引脚。

让 Agent 运行以下命令下载最新 Release 并写入 `/Volumes/RP2350/`（或让用户从 [Releases 页面](https://github.com/wasdwasd0105/USBPods-Pico2W/releases/latest) 手动下载后拖进 `RP2350` 磁盘）：

```bash
mkdir -p ~/Downloads/usbpods-fw && cd ~/Downloads/usbpods-fw
curl -fL "https://github.com/wasdwasd0105/USBPods-Pico2W/releases/latest/download/USBPods_Pico2W_Lite.uf2" -o USBPods_Pico2W_Lite.uf2
ls -lh USBPods_Pico2W_Lite.uf2
cp USBPods_Pico2W_Lite.uf2 /Volumes/RP2350/
```

拷贝完成后几秒内板子会自动重启，`RP2350` 磁盘会自动消失（macOS 右上角若提示“磁盘没有正确推出”，属于正常现象，直接关闭提示即可）。

### 4. 校验固件是否刷入成功

等待 3 秒后运行：

```bash
ls /dev/cu.usbmodem* && ioreg -r -c IOUSBHostDevice -l | grep -E "USB Product Name|idVendor|idProduct" | grep -A 2 -B 2 "USBPods"
```

正常应当能看到 `/dev/cu.usbmodem...` 串口设备，以及 `USB Product Name = "USBPods Lite ..."`（`idVendor = 51966`，即 `0xCAFE`）。

---

## 阶段三：编译并运行 macOS 图形化控制界面（`USBPodsControl`）

> 开源免费版固件本身只提供串口终端菜单（需要记 `q`/`p`/`1`/`2`/`5-8` 等快捷键），[`duceman495/USBPodsControl`](https://github.com/duceman495/USBPodsControl) 是专门为其编写的原生 macOS 图形化控制台与菜单栏应用。

### 1. 检查编译环境（macOS 14.0+）

```bash
sw_vers
swiftc --version
```

- 如果提示未安装开发者工具，执行 `xcode-select --install` 并等待命令行工具安装完成即可（**不需要**下载完整的 Xcode）。

### 2. 拉取源码、跑单元测试并一键构建

```bash
git clone https://github.com/duceman495/USBPodsControl.git
cd USBPodsControl
chmod +x build.sh
./build.sh
```

> **提示**：默认会构建到 `./dist/USBPodsControl.app`；如果想直接输出到系统「应用程序」目录，可执行：
> ```bash
> APP_OUT="/Applications/USBPodsControl.app" ./build.sh
> ```

预期末尾输出应包含：
- `ALL PARSER TESTS PASSED`
- `Done! Built: .../USBPodsControl.app`

### 3. 运行只读硬件自检（推荐）

在打开图形界面前，运行一次无破坏性的自检，验证 IOKit 串口识别、CoreAudio 声卡识别以及 `2.5s` 串口长连接稳定性：

```bash
./dist/USBPodsControl.app/Contents/MacOS/USBPodsControl --self-test
```

正常输出类似：
```text
== USBPods Hardware Self-Test ==
Discovered serial ports: ["/dev/cu.usbmodem11204 [vid=0xCAFE, name=USBPods Lite 8117, isUSBPods=true]"]
CoreAudio status: found=true, usbPodsName=USBPods, defaultOutput=..., isDefault=...
Parsed snapshot #1 & #2 stably (2.5s apart, 0 disconnects): variant='USBPods Lite', version='1.0.2', ...
```

### 4. 启动应用

```bash
open ./dist/USBPodsControl.app
```

*(若上一步输出到了 `/Applications/USBPodsControl.app`，则执行 `open /Applications/USBPodsControl.app`)*

---

## 阶段四：首次配对耳机与满血 LDAC / LHDC 设置

应用启动后，引导用户按以下顺序操作：

1. **确认板子已就绪**：顶部状态栏显示绿色圆点 + **`已就绪`**，同时系统顶部菜单栏出现耳机图标。
2. **切换 Mac 声音输出**：如果界面中「Mac 音频输出」卡片提示当前未切到 `USBPods`，直接点击 **`一键切换`**。
3. **配对蓝牙耳机**：
   - 将你的耳机进入**配对模式**（通常是长按耳机电源键/配对键直到红蓝灯或白灯快闪）；
   - 在界面点击 **`配对新耳机`**（或在「耳机槽位切换」中点击槽位 1 / 槽位 2 下的 **`配对`**）。
   - 板子进入扫描状态，几十秒内会自动连上并同步耳机名称。
4. **开启并锁定高音质编码**：
   - **实时调节 LDAC / LHDC 码率（不断连立刻生效）**：在「编码与实时码率」卡片中直接点选 `330 / 660 / 990 kbps`（LDAC）或 `256 / 400 / 500 / 900 kbps`（LHDC V5）。
   - **强制优先使用 LDAC**：如果你连上后发现走成了 `AAC`，点击卡片右上角 **`仅开 LDAC`** 预设，然后点击出现的 **`立即重连应用`** 按钮，重新握手即可走满血 LDAC。
5. **双设备快速切换**：把第二副耳机配对到「槽位 2」后，以后点一下槽位 1 / 2 的 **`切换`**（或在顶部菜单栏图标上**右键**）即可切换回连。

### 板载 LED 指示灯速查

| 闪烁规律 | 含义 |
| :--- | :--- |
| **快闪** | 正在扫描并配对新耳机 |
| **慢闪** | 正在通过蓝牙传输音频（播放中） |
| **常亮** | 空闲或已连接但未播放 |
| **闪 1 下停顿 / 闪 2 下停顿** | 正在自动回连槽位 1 / 槽位 2 |

---

## 阶段五：高频排错与二次开发提示

### 常见问题速查

1. **按住 `BOOT` 插上没出现 `/Volumes/RP2350`**
   - 90% 是用成了**纯充电线**，换一根确认能给手机传照片的 USB-C 数据线。
   - 或者先插上线，再按住 `BOOT` 不放 → 点按一次 `RESET` → 松开 `BOOT`。
2. **刷完固件找不到 `/dev/cu.usbmodem*`**
   - 拔掉重新插一次，或按一下板子上的 `RESET` 键；检查 Mac 弹窗是否需要点“允许配件连接”（macOS 隐私与安全性中的 USB 配件权限）。
3. **耳机显示已连接，但听不到声音**
   - 检查 `USBPodsControl` 里的「Mac 音频输出」卡片是否显示**已输出到 USBPods**；
   - 打开 macOS 自带的「音频 MIDI 设置」，确认 `USBPods` 设备没有被静音且采样率正常（默认 48 kHz）。
4. **`LDAC 990 kbps` 偶尔卡顿或爆音**
   - `990 kbps` 接近蓝牙经典速率极限，MacBook 铝合金机身与 USB 3.0 扩展坞会带来严重的 2.4GHz 干扰；
   - **解决办法**：用一小段 USB-C 延长线把板子离扩展坞远一点、不要使用金属外壳，或在界面中直接点选 **`660 kbps`**（音质依然远超 AAC 且极稳定）。
5. **在「设置」页修改了 `UAC2 / UAC1` 或 `48 / 44.1 kHz` 没立刻变化**
   - USB 声卡描述符仅在开机枚举时读取一次，修改后需要**重新拔插 USB 线**或按一下板子上的 **`RESET`** 键才会生效。
6. **如果你打算让 AI Agent 帮你二次定制这个 macOS 界面**
   - 如果你的 Mac 只装了 Command Line Tools 而没有装完整 Xcode，`swiftc` 会找不到 `SwiftUIMacros`，因此在 SwiftUI 视图中请避免使用 `@State` 宏，统一把状态放在 `USBPodsController` 的 `@Published` 属性中并通过 `@ObservedObject` 绑定（仓库现有代码已采用该写法，纯 CLT 可直接编译）。

---

## 相关开源项目

- **固件端**：[`wasdwasd0105/USBPods-Pico2W`](https://github.com/wasdwasd0105/USBPods-Pico2W)（GPL-3.0-only with exception）
- **macOS 图形控制端**：[`duceman495/USBPodsControl`](https://github.com/duceman495/USBPodsControl)（MIT License）
