import Cocoa
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var controller: USBPodsController!
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        controller = USBPodsController()
        setupMainWindow()
        setupMenuBar()
        observeControllerState()

        showMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutdown()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        controller.isWindowVisible = false
        return false
    }

    private func setupMainWindow() {
        let contentView = ContentView(controller: controller)
        let hostingController = NSHostingController(rootView: contentView)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "USBPods 控制台"
        window.contentViewController = hostingController
        window.setContentSize(NSSize(width: 420, height: 700))
        window.minSize = NSSize(width: 390, height: 560)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "USBPods")
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            toggleMainWindow()
            return
        }
        if event.type == .rightMouseUp {
            let menu = buildContextMenu()
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            toggleMainWindow()
        }
    }

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "打开控制面板", action: #selector(openPanelAction), keyEquivalent: ""))
        menu.addItem(.separator())

        let slot1 = NSMenuItem(title: "切换到槽位 1: \(controller.state.slot1.label)", action: #selector(selectSlot1Action), keyEquivalent: "")
        slot1.state = (controller.state.currentSlot == 1) ? .on : .off
        slot1.isEnabled = controller.isSerialConnected
        menu.addItem(slot1)

        let slot2 = NSMenuItem(title: "切换到槽位 2: \(controller.state.slot2.label)", action: #selector(selectSlot2Action), keyEquivalent: "")
        slot2.state = (controller.state.currentSlot == 2) ? .on : .off
        slot2.isEnabled = controller.isSerialConnected
        menu.addItem(slot2)

        menu.addItem(.separator())
        for kbps in [330, 660, 990] {
            let item = NSMenuItem(title: "LDAC \(kbps) kbps", action: #selector(selectLDACAction(_:)), keyEquivalent: "")
            item.tag = kbps
            item.state = (controller.state.ldacQualityKbps == kbps) ? .on : .off
            item.isEnabled = controller.isSerialConnected
            menu.addItem(item)
        }

        menu.addItem(.separator())
        if controller.state.isConnected {
            let disc = NSMenuItem(title: "断开耳机", action: #selector(disconnectEarbudsAction), keyEquivalent: "")
            disc.isEnabled = controller.isSerialConnected
            menu.addItem(disc)
        } else {
            let conn = NSMenuItem(title: "回连耳机", action: #selector(connectEarbudsAction), keyEquivalent: "")
            conn.isEnabled = controller.isSerialConnected
            menu.addItem(conn)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 USBPods 控制台", action: #selector(quitAction), keyEquivalent: "q"))

        for item in menu.items where item.action != nil {
            item.target = self
        }
        return menu
    }

    @objc private func openPanelAction() { showMainWindow() }
    @objc private func selectSlot1Action() { controller.selectSlot(1) }
    @objc private func selectSlot2Action() { controller.selectSlot(2) }
    @objc private func selectLDACAction(_ sender: NSMenuItem) { controller.setLDACQuality(sender.tag) }
    @objc private func connectEarbudsAction() { controller.connectEarbuds() }
    @objc private func disconnectEarbudsAction() { controller.disconnectEarbuds() }
    @objc private func quitAction() { NSApp.terminate(nil) }

    private func toggleMainWindow() {
        if window.isVisible && NSApp.isActive {
            window.orderOut(nil)
            controller.isWindowVisible = false
        } else {
            showMainWindow()
        }
    }

    private func showMainWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.isWindowVisible = true
    }

    private func observeControllerState() {
        controller.$state
            .combineLatest(controller.$isSerialConnected)
            .receive(on: RunLoop.main)
            .sink { [weak self] state, serialConnected in
                guard let self, let button = self.statusItem.button else { return }
                if !serialConnected {
                    button.title = ""
                } else {
                    let summary = state.menuBarSummary
                    button.title = summary.isEmpty ? "" : " \(summary)"
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: - Non-destructive Hardware Self-Test (--self-test)

func runHardwareSelfTest() -> Int32 {
    print("== USBPods Hardware Self-Test ==")
    let ports = USBDeviceDiscovery.discoverPorts()
    print("Discovered serial ports: \(ports.map { "\($0.path) [vid=\($0.vendorID.map { String(format: "0x%04X", $0) } ?? "nil"), name=\($0.productName ?? "nil"), isUSBPods=\($0.isUSBPods)]" })")

    guard let usbPodsPort = ports.first(where: { $0.isUSBPods }) else {
        fputs("ERROR: USBPods serial port not found via IOKit\n", stderr)
        return 1
    }

    let audio = CoreAudioHelper.currentStatus()
    print("CoreAudio status: found=\(audio.usbPodsDeviceFound), usbPodsName=\(audio.usbPodsDeviceName ?? "nil"), defaultOutput=\(audio.defaultOutputName ?? "nil"), isDefault=\(audio.isUSBPodsDefault)")
    guard audio.usbPodsDeviceFound else {
        fputs("ERROR: USBPods CoreAudio output device not found\n", stderr)
        return 2
    }

    let serial = SerialPort(path: usbPodsPort.path)
    let parser = USBPodsParser()
    var state = USBPodsState()
    var snapshot: USBPodsState?
    var snapshotCount = 0
    var unexpectedDisconnect: String?
    let sem1 = DispatchSemaphore(value: 0)
    let sem2 = DispatchSemaphore(value: 0)

    serial.onLine = { line in
        for ev in parser.feed(line: line, currentState: state) {
            if case let .menuSnapshot(s) = ev {
                state = s
                snapshot = s
                snapshotCount += 1
                if snapshotCount == 1 {
                    sem1.signal()
                } else if snapshotCount >= 2 {
                    sem2.signal()
                }
            }
        }
    }

    serial.onDisconnect = { reason in
        unexpectedDisconnect = reason ?? "EOF"
    }

    do {
        try serial.openPort()
    } catch {
        fputs("ERROR: failed to open serial port: \(error)\n", stderr)
        return 3
    }

    usleep(50_000)
    serial.writeString("h")
    let wait1 = sem1.wait(timeout: .now() + 2.0)
    guard wait1 == .success, let firstSnap = snapshot else {
        serial.close()
        fputs("ERROR: timed out waiting for first 'h' menu snapshot\n", stderr)
        return 4
    }

    // Wait 2.5 seconds to ensure the serial connection stays stably open
    usleep(2_500_000)
    if let disc = unexpectedDisconnect {
        serial.close()
        fputs("ERROR: serial disconnected unexpectedly during idle wait: \(disc)\n", stderr)
        return 5
    }
    guard serial.isOpen else {
        serial.close()
        fputs("ERROR: serial.isOpen became false during idle wait\n", stderr)
        return 6
    }

    serial.writeString("h")
    let wait2 = sem2.wait(timeout: .now() + 2.0)
    let stillOpenAfterSecond = serial.isOpen
    serial.close()

    guard wait2 == .success, let s = snapshot, stillOpenAfterSecond, unexpectedDisconnect == nil else {
        fputs("ERROR: failed second 'h' menu snapshot or disconnected (wait2=\(wait2 == .success), open=\(stillOpenAfterSecond), disc=\(unexpectedDisconnect ?? "nil"))\n", stderr)
        return 7
    }

    print("Parsed snapshot #1 & #2 stably (2.5s apart, 0 disconnects): variant='\(s.variant)', version='\(firstSnap.firmwareVersion)', connected=\(s.isConnected), currentSlot=\(s.currentSlot), usbMode=\(s.usbAudioMode.rawValue), sampleRate=\(s.usbSampleRate.rawValue), ldac=\(s.ldacQualityKbps)kbps, lhdc=\(s.lhdcBitrateKbps)kbps")
    return 0
}

// MARK: - Entry Point

if CommandLine.arguments.contains("--self-test") {
    exit(runHardwareSelfTest())
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
