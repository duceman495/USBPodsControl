import Foundation
import Combine

@MainActor
final class USBPodsController: ObservableObject {
    @Published var availablePorts: [SerialPortCandidate] = []
    @Published var selectedPortPath: String? = nil
    @Published var isSerialConnected: Bool = false
    @Published var connectionError: String? = nil

    @Published var state = USBPodsState()
    @Published var audioStatus = AudioOutputStatus()
    @Published var logs: [ConsoleLogEntry] = []

    @Published var bannerMessage: String? = nil
    @Published var codecNeedsReconnect: Bool = false
    @Published var usbNeedsReplug: Bool = false
    @Published var isBusy: Bool = false

    @Published var isWindowVisible: Bool = true
    @Published var isConsoleTabActive: Bool = false
    @Published var selectedTab: AppTab = .overview {
        didSet { isConsoleTabActive = (selectedTab == .console) }
    }
    @Published var showForgetAlert: Bool = false
    @Published var customCommand: String = ""

    private var serialPort: SerialPort?
    private let parser = USBPodsParser()
    private var discoveryTimer: Timer?
    private var pollingTimer: Timer?
    private var lastPollDate: Date = .distantPast
    private var commandTail: Task<Void, Never>?
    private var activeCommandCount = 0
    private var waiters: [(id: UUID, predicate: (USBPodsEvent) -> Bool, continuation: CheckedContinuation<USBPodsEvent?, Never>)] = []
    private var bannerClearTask: Task<Void, Never>?

    private let maxLogCount = 500

    init() {
        refreshPorts()
        refreshAudioStatus()
        startTimers()
        autoConnectIfAvailable()
    }

    func shutdown() {
        discoveryTimer?.invalidate()
        pollingTimer?.invalidate()
        discoveryTimer = nil
        pollingTimer = nil
        cancelAllWaiters()
        serialPort?.close()
        serialPort = nil
        isSerialConnected = false
    }

    // MARK: - Discovery & Serial Connection

    func refreshPorts() {
        let ports = USBDeviceDiscovery.discoverPorts()
        availablePorts = ports
        if let selected = selectedPortPath, ports.contains(where: { $0.path == selected }) {
            return
        }
        selectedPortPath = ports.first(where: { $0.isUSBPods })?.path ?? ports.first?.path
    }

    func refreshAudioStatus() {
        audioStatus = CoreAudioHelper.currentStatus()
    }

    func switchMacAudioToUSBPods() {
        if CoreAudioHelper.switchToUSBPodsOutput() {
            refreshAudioStatus()
            showBanner("已将 Mac 音频输出切换至 \(audioStatus.usbPodsDeviceName ?? "USBPods Lite")")
        } else {
            refreshAudioStatus()
            showBanner("未检测到 USBPods 音频设备，请检查 USB 连接")
        }
    }

    func autoConnectIfAvailable() {
        guard !isSerialConnected else { return }
        refreshPorts()
        if let preferred = availablePorts.first(where: { $0.isUSBPods })?.path {
            connectSerial(path: preferred)
        } else if let first = availablePorts.first?.path {
            connectSerial(path: first)
        }
    }

    func connectSerial(path: String? = nil) {
        let targetPath = path ?? selectedPortPath ?? availablePorts.first?.path
        guard let targetPath else {
            connectionError = "未检测到串口设备，请确认已用数据线连接板子"
            return
        }

        serialPort?.close()
        serialPort = nil
        isSerialConnected = false
        connectionError = nil
        selectedPortPath = targetPath

        let port = SerialPort(path: targetPath)
        port.onLine = { [weak self] line in
            Task { @MainActor [weak self] in
                self?.handleIncomingLine(line)
            }
        }
        port.onDisconnect = { [weak self] reason in
            Task { @MainActor [weak self] in
                self?.handleSerialDisconnected(reason: reason)
            }
        }

        do {
            try port.openPort()
            self.serialPort = port
            self.isSerialConnected = true
            self.connectionError = nil
            self.usbNeedsReplug = false
            appendLog("已连接 \(targetPath)", isOutgoing: false)

            enqueueCommand { [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: 80_000_000)
                await self.sendAndWaitMenu(timeoutMs: 1200)
                self.sendRawChar("H")
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        } catch {
            self.connectionError = error.localizedDescription
            self.isSerialConnected = false
            appendLog("连接失败: \(error.localizedDescription)", isOutgoing: false)
        }
    }

    func disconnectSerial() {
        cancelAllWaiters()
        serialPort?.close()
        serialPort = nil
        isSerialConnected = false
        appendLog("已手动断开串口连接", isOutgoing: false)
    }

    // MARK: - User Actions

    func refreshMenu() {
        enqueueCommand { [weak self] in
            await self?.sendAndWaitMenu(timeoutMs: 1000)
        }
    }

    func refreshAdvancedMenu() {
        enqueueCommand { [weak self] in
            self?.sendRawChar("H")
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    func refreshSavedDevices() {
        enqueueCommand { [weak self] in
            self?.sendRawChar("l")
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    func connectEarbuds() {
        enqueueCommand { [weak self] in
            guard let self else { return }
            self.sendRawChar("c")
            self.state.isScanning = false
            self.showBanner("正在回连当前槽位耳机...")
            try? await Task.sleep(nanoseconds: 350_000_000)
            await self.sendAndWaitMenu(timeoutMs: 1000)
        }
    }

    func disconnectEarbuds() {
        enqueueCommand { [weak self] in
            guard let self else { return }
            self.sendRawChar("d")
            self.state.isScanning = false
            self.showBanner("正在断开耳机连接...")
            try? await Task.sleep(nanoseconds: 450_000_000)
            await self.sendAndWaitMenu(timeoutMs: 1000)
        }
    }

    func selectSlot(_ slot: Int) {
        guard slot == 1 || slot == 2 else { return }
        enqueueCommand { [weak self] in
            guard let self else { return }
            self.sendRawChar(String(slot))
            self.state.currentSlot = slot
            self.state.isScanning = false
            self.showBanner("正在切换到槽位 \(slot)...")
            try? await Task.sleep(nanoseconds: 500_000_000)
            await self.sendAndWaitMenu(timeoutMs: 1000)
        }
    }

    func pairInSlot(_ slot: Int) {
        guard slot == 1 || slot == 2 else { return }
        enqueueCommand { [weak self] in
            guard let self else { return }
            if self.state.isConnected {
                self.sendRawChar("d")
                try? await Task.sleep(nanoseconds: 650_000_000)
            }
            if self.state.currentSlot != slot {
                self.sendRawChar(String(slot))
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
            self.sendRawChar("p")
            self.state.isScanning = true
            self.state.isConnected = false
            self.showBanner("槽位 \(slot) 正在扫描配对，请让耳机进入配对模式")
            try? await Task.sleep(nanoseconds: 450_000_000)
            await self.sendAndWaitMenu(timeoutMs: 1000)
        }
    }

    func setLDACQuality(_ targetKbps: Int) {
        guard [330, 660, 990].contains(targetKbps) else { return }
        enqueueCommand { [weak self] in
            guard let self else { return }
            for _ in 0..<3 {
                if self.state.ldacQualityKbps == targetKbps { break }
                let event = await self.sendAndWait("q", timeoutMs: 400) { ev in
                    if case .ldacQualityChanged = ev { return true }
                    return false
                }
                if case let .ldacQualityChanged(kbps) = event {
                    self.state.ldacQualityKbps = kbps
                    if kbps == targetKbps { break }
                } else {
                    break
                }
            }
            await self.sendAndWaitMenu(timeoutMs: 900)
            self.showBanner("LDAC 码率已设为 \(self.state.ldacQualityKbps) kbps")
        }
    }

    func setLHDCBitrate(_ targetKbps: Int) {
        guard [256, 400, 500, 900].contains(targetKbps) else { return }
        enqueueCommand { [weak self] in
            guard let self else { return }
            for _ in 0..<4 {
                if self.state.lhdcBitrateKbps == targetKbps { break }
                let event = await self.sendAndWait("e", timeoutMs: 400) { ev in
                    if case .lhdcBitrateChanged = ev { return true }
                    return false
                }
                if case let .lhdcBitrateChanged(kbps) = event {
                    self.state.lhdcBitrateKbps = kbps
                    if kbps == targetKbps { break }
                } else {
                    break
                }
            }
            await self.sendAndWaitMenu(timeoutMs: 900)
            self.showBanner("LHDC 码率已设为 \(self.state.lhdcBitrateKbps) kbps")
        }
    }

    func setEarbudButtonMode(_ target: EarbudButtonMode) {
        enqueueCommand { [weak self] in
            guard let self else { return }
            for _ in 0..<4 {
                if self.state.earbudButtonMode == target { break }
                let event = await self.sendAndWait("b", timeoutMs: 400) { ev in
                    if case .earbudButtonChanged = ev { return true }
                    return false
                }
                if case let .earbudButtonChanged(mode) = event {
                    self.state.earbudButtonMode = mode
                    if mode == target { break }
                } else {
                    break
                }
            }
            await self.sendAndWaitMenu(timeoutMs: 900)
            self.showBanner("耳机按键已设为：\(self.state.earbudButtonMode.displayName)")
        }
    }

    func setCodecEnabled(_ codec: String, enabled: Bool) {
        enqueueCommand { [weak self] in
            guard let self else { return }
            let keyAndCurrent: (key: String, current: Bool)? = {
                switch codec {
                case "AAC-ELD": return ("5", self.state.codecAacEldEnabled)
                case "LHDC":    return ("6", self.state.codecLhdcEnabled)
                case "LDAC":    return ("7", self.state.codecLdacEnabled)
                case "AAC":     return ("8", self.state.codecAacEnabled)
                default:        return nil
                }
            }()
            guard let pair = keyAndCurrent, pair.current != enabled else { return }
            _ = await self.sendAndWait(pair.key, timeoutMs: 400) { ev in
                if case .codecToggled = ev { return true }
                return false
            }
            await self.sendAndWaitMenu(timeoutMs: 900)
            if self.state.isConnected {
                self.codecNeedsReconnect = true
            }
            self.showBanner("\(codec) 已\(enabled ? "开启" : "关闭")（下次连接生效）")
        }
    }

    func applyLDACOnlyPreset() {
        enqueueCommand { [weak self] in
            guard let self else { return }
            let steps: [(key: String, current: Bool, target: Bool)] = [
                ("5", self.state.codecAacEldEnabled, false),
                ("6", self.state.codecLhdcEnabled, false),
                ("7", self.state.codecLdacEnabled, true),
                ("8", self.state.codecAacEnabled, false)
            ]
            for step in steps where step.current != step.target {
                _ = await self.sendAndWait(step.key, timeoutMs: 400) { ev in
                    if case .codecToggled = ev { return true }
                    return false
                }
            }
            await self.sendAndWaitMenu(timeoutMs: 900)
            if self.state.isConnected && self.state.activeCodec != "LDAC" {
                self.codecNeedsReconnect = true
            }
            self.showBanner("已应用「仅开启 LDAC」预设")
        }
    }

    func applyAllCodecsPreset() {
        enqueueCommand { [weak self] in
            guard let self else { return }
            let steps: [(key: String, current: Bool, target: Bool)] = [
                ("5", self.state.codecAacEldEnabled, true),
                ("6", self.state.codecLhdcEnabled, true),
                ("7", self.state.codecLdacEnabled, true),
                ("8", self.state.codecAacEnabled, true)
            ]
            for step in steps where step.current != step.target {
                _ = await self.sendAndWait(step.key, timeoutMs: 400) { ev in
                    if case .codecToggled = ev { return true }
                    return false
                }
            }
            await self.sendAndWaitMenu(timeoutMs: 900)
            if self.state.isConnected {
                self.codecNeedsReconnect = true
            }
            self.showBanner("已开启全部高清编码")
        }
    }

    func reconnectToApplyCodecs() {
        enqueueCommand { [weak self] in
            guard let self else { return }
            self.codecNeedsReconnect = false
            self.showBanner("正在重连耳机以重新协商编码...")
            self.sendRawChar("d")
            try? await Task.sleep(nanoseconds: 900_000_000)
            self.sendRawChar("c")
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await self.sendAndWaitMenu(timeoutMs: 1000)
        }
    }

    func setAutoConnect(_ enabled: Bool) {
        enqueueCommand { [weak self] in
            guard let self, self.state.autoConnectOnPower != enabled else { return }
            _ = await self.sendAndWait("w", timeoutMs: 400) { ev in
                if case .autoConnectChanged = ev { return true }
                return false
            }
            await self.sendAndWaitMenu(timeoutMs: 900)
        }
    }

    func setPauseOnDisconnect(_ enabled: Bool) {
        enqueueCommand { [weak self] in
            guard let self, self.state.pauseOnDisconnect != enabled else { return }
            _ = await self.sendAndWait("z", timeoutMs: 400) { ev in
                if case .pauseOnDisconnectChanged = ev { return true }
                return false
            }
            await self.sendAndWaitMenu(timeoutMs: 900)
        }
    }

    func setUSBAudioMode(_ mode: USBAudioMode) {
        enqueueCommand { [weak self] in
            guard let self, self.state.usbAudioMode != mode else { return }
            _ = await self.sendAndWait("u", timeoutMs: 400) { ev in
                if case .usbAudioModeChanged = ev { return true }
                return false
            }
            await self.sendAndWaitMenu(timeoutMs: 900)
            self.usbNeedsReplug = true
            self.showBanner("USB 模式已改为 \(mode.rawValue)，请重新插拔 USB 线生效")
        }
    }

    func setUSBSampleRate(_ rate: USBSampleRate) {
        enqueueCommand { [weak self] in
            guard let self, self.state.usbSampleRate != rate else { return }
            _ = await self.sendAndWait("k", timeoutMs: 400) { ev in
                if case .usbSampleRateChanged = ev { return true }
                return false
            }
            await self.sendAndWaitMenu(timeoutMs: 900)
            self.usbNeedsReplug = true
            self.showBanner("采样率已改为 \(rate.rawValue)，请重新插拔 USB 线生效")
        }
    }

    func setHFPBatteryEnabled(_ enabled: Bool) {
        enqueueCommand { [weak self] in
            guard let self else { return }
            if let cur = self.state.hfpBatteryEnabled, cur == enabled { return }
            _ = await self.sendAndWait("Y", timeoutMs: 400) { ev in
                if case .hfpBatteryChanged = ev { return true }
                return false
            }
            self.sendRawChar("H")
            try? await Task.sleep(nanoseconds: 250_000_000)
            self.showBanner("HFP 电量回传已\(enabled ? "开启" : "关闭")（重启板子生效）")
        }
    }

    func setDebugModeEnabled(_ enabled: Bool) {
        enqueueCommand { [weak self] in
            guard let self else { return }
            if let cur = self.state.debugModeEnabled, cur == enabled { return }
            _ = await self.sendAndWait("D", timeoutMs: 400) { ev in
                if case .debugModeChanged = ev { return true }
                return false
            }
            self.sendRawChar("H")
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    func kickAudioStream() {
        enqueueCommand { [weak self] in
            guard let self else { return }
            self.sendRawChar("K")
            self.showBanner("已发送重启音频流指令")
            try? await Task.sleep(nanoseconds: 500_000_000)
            await self.sendAndWaitMenu(timeoutMs: 900)
        }
    }

    func forgetAllPairings() {
        enqueueCommand { [weak self] in
            guard let self else { return }
            _ = await self.sendAndWait("r", timeoutMs: 400) { ev in
                if case .wipeConfirmationPrompt = ev { return true }
                return false
            }
            _ = await self.sendAndWait("y", timeoutMs: 600) { ev in
                if case .allPairingsDeleted = ev { return true }
                return false
            }
            self.state.isConnected = false
            self.state.isPlaying = false
            self.state.isScanning = false
            self.state.connectedDeviceName = nil
            await self.sendAndWaitMenu(timeoutMs: 1000)
            self.showBanner("已清除全部配对记录")
        }
    }

    // Media & Volume
    func previousTrack() { sendRawChar(".") }
    func playPause()     { sendRawChar("/") }
    func nextTrack()     { sendRawChar(",") }
    func volumeDown()    { sendRawChar("]") }
    func volumeUp()      { sendRawChar("[") }

    func sendCustomCommand(_ text: String) {
        guard !text.isEmpty, isSerialConnected else { return }
        appendLog("> \(text)", isOutgoing: true)
        serialPort?.writeString(text)
    }

    func clearLogs() {
        logs.removeAll()
    }

    // MARK: - Internals

    private func sendRawChar(_ ch: String) {
        guard isSerialConnected, let serialPort else { return }
        appendLog("> \(ch)", isOutgoing: true)
        serialPort.writeString(ch)
    }

    private func enqueueCommand(_ operation: @escaping @MainActor () async -> Void) {
        let previous = commandTail
        let nextTask = Task { @MainActor [weak self] in
            if let previous {
                _ = await previous.result
            }
            guard let self else { return }
            self.activeCommandCount += 1
            self.isBusy = true
            defer {
                self.activeCommandCount = max(0, self.activeCommandCount - 1)
                self.isBusy = self.activeCommandCount > 0
            }
            await operation()
        }
        commandTail = nextTask
    }

    @discardableResult
    private func sendAndWaitMenu(timeoutMs: Int) async -> USBPodsEvent? {
        await sendAndWait("h", timeoutMs: timeoutMs) { ev in
            if case .menuSnapshot = ev { return true }
            return false
        }
    }

    private func sendAndWait(
        _ chars: String,
        timeoutMs: Int,
        matching predicate: @escaping (USBPodsEvent) -> Bool
    ) async -> USBPodsEvent? {
        guard isSerialConnected, let serialPort else { return nil }
        let waiterID = UUID()

        return await withCheckedContinuation { continuation in
            self.waiters.append((id: waiterID, predicate: predicate, continuation: continuation))
            self.appendLog("> \(chars)", isOutgoing: true)
            serialPort.writeString(chars)

            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeoutMs) * 1_000_000)
                guard let self else { return }
                if let idx = self.waiters.firstIndex(where: { $0.id == waiterID }) {
                    let waiter = self.waiters.remove(at: idx)
                    waiter.continuation.resume(returning: nil)
                }
            }
        }
    }

    private func cancelAllWaiters() {
        let pending = waiters
        waiters.removeAll()
        for w in pending {
            w.continuation.resume(returning: nil)
        }
    }

    private func handleIncomingLine(_ line: String) {
        if !line.isEmpty {
            appendLog(line, isOutgoing: false)
        }

        let events = parser.feed(line: line, currentState: state)
        for event in events {
            applyEvent(event)
            resolveWaiters(with: event)
        }
    }

    private func applyEvent(_ event: USBPodsEvent) {
        switch event {
        case let .menuSnapshot(snapshot):
            let wasScanning = state.isScanning
            state = snapshot
            if snapshot.isConnected {
                state.isScanning = false
            } else {
                state.isScanning = wasScanning
            }

        case let .scanningStarted(slot):
            state.currentSlot = slot
            state.isScanning = true
            state.isConnected = false

        case let .ldacQualityChanged(kbps):
            state.ldacQualityKbps = kbps

        case let .lhdcBitrateChanged(kbps):
            state.lhdcBitrateKbps = kbps

        case let .earbudButtonChanged(mode):
            state.earbudButtonMode = mode

        case let .codecToggled(name, enabled):
            switch name {
            case "AAC-ELD": state.codecAacEldEnabled = enabled
            case "LHDC V5": state.codecLhdcEnabled = enabled
            case "LDAC":    state.codecLdacEnabled = enabled
            case "AAC":     state.codecAacEnabled = enabled
            default: break
            }

        case let .autoConnectChanged(val):
            state.autoConnectOnPower = val

        case let .pauseOnDisconnectChanged(val):
            state.pauseOnDisconnect = val

        case let .usbAudioModeChanged(mode):
            state.usbAudioMode = mode

        case let .usbSampleRateChanged(rate):
            state.usbSampleRate = rate

        case let .hfpBatteryChanged(enabled):
            state.hfpBatteryEnabled = enabled

        case let .debugModeChanged(enabled):
            state.debugModeEnabled = enabled

        case .allPairingsDeleted:
            state.isConnected = false
            state.isPlaying = false
            state.isScanning = false
            state.connectedDeviceName = nil
            state.slot1 = .empty(1)
            state.slot2 = .empty(2)

        case let .slotAlreadyConnected(slot):
            state.currentSlot = slot

        case let .slotSwitching(slot), let .slotDialing(slot):
            state.currentSlot = slot

        case .connectedEvent:
            state.isScanning = false
            codecNeedsReconnect = false
            enqueueCommand { [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                await self?.sendAndWaitMenu(timeoutMs: 900)
            }

        case .disconnectedEvent:
            state.isConnected = false
            state.isPlaying = false
            enqueueCommand { [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                await self?.sendAndWaitMenu(timeoutMs: 900)
            }

        case .wipeConfirmationPrompt:
            break
        }
    }

    private func resolveWaiters(with event: USBPodsEvent) {
        var remaining: [(id: UUID, predicate: (USBPodsEvent) -> Bool, continuation: CheckedContinuation<USBPodsEvent?, Never>)] = []
        for waiter in waiters {
            if waiter.predicate(event) {
                waiter.continuation.resume(returning: event)
            } else {
                remaining.append(waiter)
            }
        }
        waiters = remaining
    }

    private func handleSerialDisconnected(reason: String?) {
        cancelAllWaiters()
        serialPort = nil
        isSerialConnected = false
        state.isConnected = false
        state.isPlaying = false
        state.isScanning = false
        if let reason, !reason.isEmpty {
            connectionError = reason
            appendLog("串口已断开: \(reason)", isOutgoing: false)
        } else {
            appendLog("串口设备已拔出", isOutgoing: false)
        }
        refreshPorts()
        refreshAudioStatus()
    }

    private func startTimers() {
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshAudioStatus()
                if !self.isSerialConnected {
                    self.autoConnectIfAvailable()
                }
            }
        }

        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.isSerialConnected, self.activeCommandCount == 0 else { return }
                if self.isConsoleTabActive && self.isWindowVisible {
                    return
                }
                let interval: TimeInterval = self.isWindowVisible ? 2.5 : 5.0
                if Date().timeIntervalSince(self.lastPollDate) >= interval {
                    self.lastPollDate = Date()
                    self.enqueueCommand { [weak self] in
                        await self?.sendAndWaitMenu(timeoutMs: 900)
                    }
                }
            }
        }
    }

    private func appendLog(_ text: String, isOutgoing: Bool) {
        logs.append(ConsoleLogEntry(text: text, isOutgoing: isOutgoing))
        if logs.count > maxLogCount {
            logs.removeFirst(logs.count - maxLogCount)
        }
    }

    private func showBanner(_ text: String) {
        bannerClearTask?.cancel()
        bannerMessage = text
        bannerClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            self?.bannerMessage = nil
        }
    }
}
