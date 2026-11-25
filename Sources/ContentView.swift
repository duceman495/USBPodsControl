import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case overview = "概览"
    case settings = "设置"
    case console  = "终端"

    var id: String { rawValue }
}

struct ContentView: View {
    @ObservedObject var controller: USBPodsController

    var body: some View {
        VStack(spacing: 0) {
            topHeaderBar
            Divider()

            if let banner = controller.bannerMessage {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.accentColor)
                    Text(banner)
                        .font(.caption)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.accentColor.opacity(0.12))
                Divider()
            }

            Group {
                switch controller.selectedTab {
                case .overview:
                    overviewView
                case .settings:
                    settingsView
                case .console:
                    consoleView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 390, minHeight: 560)
        .alert("确认清除全部配对记录？", isPresented: $controller.showForgetAlert) {
            Button("取消", role: .cancel) {}
            Button("全部清除", role: .destructive) {
                controller.forgetAllPairings()
            }
        } message: {
            Text("这会删除芯片内保存的所有蓝牙链路密钥以及槽位 1、槽位 2 记录，之后需要重新配对耳机。")
        }
    }

    // MARK: - Top Header

    private var topHeaderBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(controller.isSerialConnected ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)

                Text(controller.state.variant)
                    .font(.headline)

                if !controller.state.firmwareVersion.isEmpty {
                    Text("v\(controller.state.firmwareVersion)")
                        .font(.caption.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)
                }

                Spacer()

                if controller.isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 2)
                }

                portMenuButton
            }

            Picker("", selection: $controller.selectedTab) {
                ForEach(AppTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var portMenuButton: some View {
        Menu {
            if controller.availablePorts.isEmpty {
                Text("未检测到 USB 串口设备")
            } else {
                ForEach(controller.availablePorts) { port in
                    Button {
                        controller.connectSerial(path: port.path)
                    } label: {
                        if port.path == controller.selectedPortPath && controller.isSerialConnected {
                            Label(port.displayLabel, systemImage: "checkmark")
                        } else {
                            Text(port.displayLabel)
                        }
                    }
                }
            }
            Divider()
            Button("刷新串口列表") {
                controller.refreshPorts()
                controller.autoConnectIfAvailable()
            }
            if controller.isSerialConnected {
                Button("刷新面板状态") {
                    controller.refreshMenu()
                }
                Button("断开串口") {
                    controller.disconnectSerial()
                }
            } else {
                Button("立即连接") {
                    controller.connectSerial()
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: controller.isSerialConnected ? "cable.connector" : "exclamationmark.triangle")
                    .font(.caption)
                Text(controller.isSerialConnected ? "已就绪" : "未连接")
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12))
            .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Overview Tab

    private var overviewView: some View {
        ScrollView {
            VStack(spacing: 12) {
                if !controller.isSerialConnected {
                    disconnectedHardwareBanner
                }

                headsetHeroCard
                macAudioOutputCard
                slotsCard
                codecAndBitrateCard
                mediaControlCard
            }
            .padding(14)
        }
    }

    private var disconnectedHardwareBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "usb")
                .font(.title3)
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("未连接到 RP2350 发射器")
                    .font(.subheadline.weight(.semibold))
                Text(controller.connectionError ?? "请用数据线将微雪 RP2350B-Plus-W 插入 Mac")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("重试") {
                controller.refreshPorts()
                controller.connectSerial()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(10)
    }

    private var headsetHeroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: controller.state.isConnected ? "headphones" : (controller.state.isScanning ? "dot.radiowaves.left.and.right" : "headphones.circle"))
                            .font(.title2)
                            .foregroundColor(controller.state.isConnected ? .green : (controller.state.isScanning ? .blue : .secondary))

                        Text(heroTitleText)
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        Text(heroSubtitleText)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if controller.state.isPlaying {
                            Label("播放中", systemImage: "waveform")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                        }
                    }
                }

                Spacer()

                if controller.state.isConnected, let codec = controller.state.activeCodec {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(codec)
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(codec == "LDAC" ? .orange : .accentColor)
                        if let kbps = controller.state.activeBitrateKbps, kbps > 0 {
                            Text("\(kbps) kbps")
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background((codec == "LDAC" ? Color.orange : Color.accentColor).opacity(0.14))
                    .cornerRadius(8)
                }
            }

            if controller.state.isConnected && controller.state.hasAnyBatteryInfo {
                HStack(spacing: 12) {
                    if let hb = controller.state.hfpBatteryPercent {
                        batteryPill(title: "耳机电量", value: "\(hb)%")
                    }
                    if let left = controller.state.leftBattery {
                        batteryPill(title: "左耳", value: left.formatted)
                    }
                    if let right = controller.state.rightBattery {
                        batteryPill(title: "右耳", value: right.formatted)
                    }
                    if let caseBat = controller.state.caseBattery {
                        batteryPill(title: "充电盒", value: caseBat.formatted)
                    }
                }
            }

            HStack(spacing: 8) {
                if controller.state.isConnected {
                    Button {
                        controller.disconnectEarbuds()
                    } label: {
                        Label("断开耳机", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!controller.isSerialConnected)
                } else {
                    Button {
                        controller.connectEarbuds()
                    } label: {
                        Label("回连耳机", systemImage: "link")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!controller.isSerialConnected)
                }

                Button {
                    controller.pairInSlot(controller.state.currentSlot)
                } label: {
                    Label(controller.state.isScanning ? "扫描配对中..." : "配对新耳机", systemImage: "antenna.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!controller.isSerialConnected)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private func batteryPill(title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "battery.75")
                .font(.caption2)
                .foregroundColor(.green)
            Text("\(title) \(value)")
                .font(.caption2.monospacedDigit())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(5)
    }

    private var heroTitleText: String {
        if controller.state.isConnected {
            return controller.state.connectedDeviceName ?? "蓝牙耳机已连接"
        }
        if controller.state.isScanning {
            return "正在扫描配对耳机..."
        }
        return "未连接蓝牙耳机"
    }

    private var heroSubtitleText: String {
        if controller.state.isConnected {
            return "当前通过槽位 \(controller.state.currentSlot) 传输音频"
        }
        if controller.state.isScanning {
            return "请将耳机置于配对状态，板子会自动连接"
        }
        return "当前默认槽位 \(controller.state.currentSlot)"
    }

    private var macAudioOutputCard: some View {
        HStack(spacing: 10) {
            Image(systemName: controller.audioStatus.isUSBPodsDefault ? "speaker.wave.2.circle.fill" : "speaker.slash.circle")
                .font(.title3)
                .foregroundColor(controller.audioStatus.isUSBPodsDefault ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Mac 音频输出")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if controller.audioStatus.isUSBPodsDefault {
                    Text("已输出到 \(controller.audioStatus.defaultOutputName ?? "USBPods Lite")")
                        .font(.subheadline.weight(.medium))
                } else if controller.audioStatus.usbPodsDeviceFound {
                    Text("当前是「\(controller.audioStatus.defaultOutputName ?? "其他设备")」，未切到 USBPods")
                        .font(.subheadline)
                } else {
                    Text("未在 macOS 声音列表发现 USBPods")
                        .font(.subheadline)
                }
            }

            Spacer()

            if controller.audioStatus.usbPodsDeviceFound && !controller.audioStatus.isUSBPodsDefault {
                Button("一键切换") {
                    controller.switchMacAudioToUSBPods()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private var slotsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("耳机槽位切换")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("点击卡片切换并回连")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                slotBox(controller.state.slot1)
                slotBox(controller.state.slot2)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private func slotBox(_ slot: SlotInfo) -> some View {
        let isCurrent = (controller.state.currentSlot == slot.number)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("槽位 \(slot.number)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(isCurrent ? .accentColor : .secondary)
                Spacer()
                if isCurrent {
                    Text("当前")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.16))
                        .foregroundColor(.accentColor)
                        .cornerRadius(4)
                }
            }

            Text(slot.label)
                .font(.subheadline.weight(.medium))
                .foregroundColor(slot.isEmpty ? .secondary : .primary)
                .lineLimit(1)

            HStack(spacing: 6) {
                Button(slot.isEmpty ? "选中" : "切换") {
                    controller.selectSlot(slot.number)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!controller.isSerialConnected)

                Button("配对") {
                    controller.pairInSlot(slot.number)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!controller.isSerialConnected)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isCurrent ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isCurrent ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    private var codecAndBitrateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("编码与实时码率")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("仅开 LDAC") {
                    controller.applyLDACOnlyPreset()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(!controller.isSerialConnected)

                Button("全部开启") {
                    controller.applyAllCodecsPreset()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(!controller.isSerialConnected)
            }

            // LDAC live quality
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("LDAC 码率（不断连实时生效）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(controller.state.ldacQualityKbps) kbps")
                        .font(.caption.monospacedDigit().weight(.medium))
                }
                HStack(spacing: 6) {
                    ForEach([330, 660, 990], id: \.self) { kbps in
                        bitrateButton(
                            title: "\(kbps) kbps",
                            isSelected: controller.state.ldacQualityKbps == kbps,
                            tint: .orange
                        ) {
                            controller.setLDACQuality(kbps)
                        }
                    }
                }
            }

            // LHDC live bitrate
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("LHDC V5 码率（不断连实时生效）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(controller.state.lhdcBitrateKbps) kbps")
                        .font(.caption.monospacedDigit().weight(.medium))
                }
                HStack(spacing: 6) {
                    ForEach([256, 400, 500, 900], id: \.self) { kbps in
                        bitrateButton(
                            title: "\(kbps)k",
                            isSelected: controller.state.lhdcBitrateKbps == kbps,
                            tint: .accentColor
                        ) {
                            controller.setLHDCBitrate(kbps)
                        }
                    }
                }
            }

            Divider()

            VStack(spacing: 6) {
                Text("允许协商的编码（关闭其他编码可强制走 LDAC，下次连接生效）")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    codecToggleRow("LDAC", isOn: controller.state.codecLdacEnabled) { val in
                        controller.setCodecEnabled("LDAC", enabled: val)
                    }
                    codecToggleRow("LHDC V5", isOn: controller.state.codecLhdcEnabled) { val in
                        controller.setCodecEnabled("LHDC", enabled: val)
                    }
                    codecToggleRow("AAC-ELD (AirPods)", isOn: controller.state.codecAacEldEnabled) { val in
                        controller.setCodecEnabled("AAC-ELD", enabled: val)
                    }
                    codecToggleRow("AAC", isOn: controller.state.codecAacEnabled) { val in
                        controller.setCodecEnabled("AAC", enabled: val)
                    }
                }
            }

            if controller.codecNeedsReconnect && controller.isSerialConnected {
                HStack {
                    Text("编码开关已变更，重连耳机后生效")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Spacer()
                    Button("立即重连应用") {
                        controller.reconnectToApplyCodecs()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(8)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(6)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private func bitrateButton(title: String, isSelected: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(isSelected ? tint.opacity(0.2) : Color.secondary.opacity(0.08))
                .foregroundColor(isSelected ? tint : .primary)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? tint : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!controller.isSerialConnected)
    }

    private func codecToggleRow(_ label: String, isOn: Bool, onChange: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: { onChange($0) })) {
            Text(label)
                .font(.caption)
                .lineLimit(1)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .disabled(!controller.isSerialConnected)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(6)
    }

    private var mediaControlCard: some View {
        HStack(spacing: 8) {
            Button {
                controller.previousTrack()
            } label: {
                Image(systemName: "backward.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                controller.playPause()
            } label: {
                Image(systemName: "playpause.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                controller.nextTrack()
            } label: {
                Image(systemName: "forward.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Divider()
                .frame(height: 18)

            Button {
                controller.volumeDown()
            } label: {
                Image(systemName: "speaker.minus.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                controller.volumeUp()
            } label: {
                Image(systemName: "speaker.plus.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .disabled(!controller.isSerialConnected)
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Settings Tab

    private var settingsView: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("连接与操控")
                        .font(.subheadline.weight(.semibold))

                    Toggle("通电自动回连耳机 (w)", isOn: Binding(
                        get: { controller.state.autoConnectOnPower },
                        set: { controller.setAutoConnect($0) }
                    ))
                    .disabled(!controller.isSerialConnected)

                    Toggle("耳机断开时自动暂停 Mac 播放 (z)", isOn: Binding(
                        get: { controller.state.pauseOnDisconnect },
                        set: { controller.setPauseOnDisconnect($0) }
                    ))
                    .disabled(!controller.isSerialConnected)

                    HStack {
                        Text("耳机物理按键 (b)")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { controller.state.earbudButtonMode },
                            set: { controller.setEarbudButtonMode($0) }
                        )) {
                            ForEach(EarbudButtonMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 195)
                        .disabled(!controller.isSerialConnected)
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.18), lineWidth: 1))

                VStack(alignment: .leading, spacing: 10) {
                    Text("USB 声卡参数（修改后需重新插拔 USB）")
                        .font(.subheadline.weight(.semibold))

                    HStack {
                        Text("USB 音频模式 (u)")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { controller.state.usbAudioMode },
                            set: { controller.setUSBAudioMode($0) }
                        )) {
                            ForEach(USBAudioMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                        .disabled(!controller.isSerialConnected)
                    }

                    HStack {
                        Text("USB 采样率 (k)")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { controller.state.usbSampleRate },
                            set: { controller.setUSBSampleRate($0) }
                        )) {
                            ForEach(USBSampleRate.allCases, id: \.self) { rate in
                                Text(rate.rawValue).tag(rate)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                        .disabled(!controller.isSerialConnected)
                    }

                    if controller.usbNeedsReplug {
                        Text("USB 声卡描述符参数已更新，请重新插拔数据线或按一下板子上的 RESET 键使其生效。")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.18), lineWidth: 1))

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("高级与维护")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button("读取高级状态") {
                            controller.refreshAdvancedMenu()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(!controller.isSerialConnected)
                    }

                    Toggle("HFP 耳机电量回传 (Y，重启生效)", isOn: Binding(
                        get: { controller.state.hfpBatteryEnabled ?? false },
                        set: { controller.setHFPBatteryEnabled($0) }
                    ))
                    .disabled(!controller.isSerialConnected)

                    Toggle("固件协议调试日志 (D)", isOn: Binding(
                        get: { controller.state.debugModeEnabled ?? false },
                        set: { controller.setDebugModeEnabled($0) }
                    ))
                    .disabled(!controller.isSerialConnected)

                    HStack(spacing: 10) {
                        Button {
                            controller.kickAudioStream()
                        } label: {
                            Label("重启音频流 (K)", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!controller.isSerialConnected)

                        Button(role: .destructive) {
                            controller.showForgetAlert = true
                        } label: {
                            Label("清除全部配对 (r)", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!controller.isSerialConnected)
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.18), lineWidth: 1))
            }
            .padding(14)
        }
    }

    // MARK: - Console Tab

    private var consoleView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Button("菜单 (h)") { controller.refreshMenu() }
                Button("高级 (H)") { controller.refreshAdvancedMenu() }
                Button("设备 (l)") { controller.refreshSavedDevices() }
                Button("报告 (R)") { controller.sendCustomCommand("R") }
                Spacer()
                Button("清空") { controller.clearLogs() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!controller.isSerialConnected)
            .padding(.horizontal, 12)
            .padding(.top, 10)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(controller.logs) { entry in
                            Text(entry.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(entry.isOutgoing ? .cyan : .green)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(entry.id)
                        }
                    }
                    .padding(10)
                }
                .background(Color.black.opacity(0.9))
                .cornerRadius(8)
                .padding(.horizontal, 12)
                .onChange(of: controller.logs.count) { _, _ in
                    if let last = controller.logs.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("输入单字符或指令（如 h, q, R）...", text: $controller.customCommand)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        submitCustomCommand()
                    }
                Button("发送") {
                    submitCustomCommand()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!controller.isSerialConnected || controller.customCommand.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private func submitCustomCommand() {
        let cmd = controller.customCommand
        guard !cmd.isEmpty else { return }
        controller.customCommand = ""
        controller.sendCustomCommand(cmd)
    }
}
