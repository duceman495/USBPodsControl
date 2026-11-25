import Foundation

enum USBAudioMode: String, CaseIterable, Equatable {
    case uac2 = "UAC2"
    case uac1 = "UAC1"

    var displayName: String {
        switch self {
        case .uac2: return "UAC2 (推荐)"
        case .uac1: return "UAC1 (兼容老设备)"
        }
    }
}

enum USBSampleRate: String, CaseIterable, Equatable {
    case khz48 = "48 kHz"
    case khz44_1 = "44.1 kHz"
}

enum EarbudButtonMode: Int, CaseIterable, Equatable, Identifiable {
    case volume = 1
    case restartStream = 2
    case playPause = 3
    case doNothing = 4

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .volume: return "短按音量+ / 长按音量-"
        case .restartStream: return "重启音频流"
        case .playPause: return "播放 / 暂停"
        case .doNothing: return "无动作"
        }
    }

    static func fromFirmwareString(_ raw: String) -> EarbudButtonMode? {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.contains("volume") { return .volume }
        if lower.contains("restart") { return .restartStream }
        if lower.contains("play") { return .playPause }
        if lower.contains("nothing") { return .doNothing }
        return nil
    }
}

struct BatteryLevel: Equatable {
    var percent: Int
    var charging: Bool

    var formatted: String {
        "\(percent)%\(charging ? "⚡" : "")"
    }
}

struct SlotInfo: Equatable {
    var number: Int
    var label: String
    var isEmpty: Bool

    static func empty(_ number: Int) -> SlotInfo {
        SlotInfo(number: number, label: "空槽位", isEmpty: true)
    }
}

struct USBPodsState: Equatable {
    var variant: String = "USBPods Lite"
    var firmwareVersion: String = ""

    var isConnected: Bool = false
    var isPlaying: Bool = false
    var isScanning: Bool = false
    var connectedDeviceName: String? = nil

    var activeCodec: String? = nil
    var activeBitrateKbps: Int? = nil

    var hfpBatteryPercent: Int? = nil
    var leftBattery: BatteryLevel? = nil
    var rightBattery: BatteryLevel? = nil
    var caseBattery: BatteryLevel? = nil

    var currentSlot: Int = 1
    var slot1: SlotInfo = .empty(1)
    var slot2: SlotInfo = .empty(2)

    var autoConnectOnPower: Bool = true
    var pauseOnDisconnect: Bool = true
    var usbAudioMode: USBAudioMode = .uac2
    var usbSampleRate: USBSampleRate = .khz48
    var earbudButtonMode: EarbudButtonMode = .volume
    var ldacQualityKbps: Int = 660
    var lhdcBitrateKbps: Int = 400

    var codecAacEldEnabled: Bool = true
    var codecLhdcEnabled: Bool = true
    var codecLdacEnabled: Bool = true
    var codecAacEnabled: Bool = true

    var hfpBatteryEnabled: Bool? = nil
    var debugModeEnabled: Bool? = nil

    var hasAnyBatteryInfo: Bool {
        hfpBatteryPercent != nil || leftBattery != nil || rightBattery != nil || caseBattery != nil
    }

    var menuBarSummary: String {
        if isScanning {
            return "配对中"
        }
        if isConnected {
            if let codec = activeCodec {
                if let kb = activeBitrateKbps, kb > 0 {
                    return "\(codec) \(kb)k"
                }
                return codec
            }
            return "已连接"
        }
        return ""
    }
}

struct SerialPortCandidate: Identifiable, Equatable, Hashable {
    var id: String { path }
    let path: String
    let productName: String?
    let vendorID: Int?
    let productID: Int?
    let serialNumber: String?
    let isUSBPods: Bool

    var displayLabel: String {
        let shortPath = (path as NSString).lastPathComponent
        if let name = productName, !name.isEmpty {
            return "\(name) (\(shortPath))"
        }
        return shortPath
    }
}

struct ConsoleLogEntry: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let text: String
    let isOutgoing: Bool

    init(id: UUID = UUID(), timestamp: Date = Date(), text: String, isOutgoing: Bool = false) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.isOutgoing = isOutgoing
    }
}

struct AudioOutputStatus: Equatable {
    var usbPodsDeviceFound: Bool = false
    var usbPodsDeviceName: String? = nil
    var defaultOutputName: String? = nil
    var isUSBPodsDefault: Bool = false
}

enum USBPodsEvent: Equatable {
    case menuSnapshot(USBPodsState)
    case scanningStarted(slot: Int)
    case ldacQualityChanged(kbps: Int)
    case lhdcBitrateChanged(kbps: Int)
    case earbudButtonChanged(EarbudButtonMode)
    case codecToggled(name: String, enabled: Bool)
    case autoConnectChanged(Bool)
    case pauseOnDisconnectChanged(Bool)
    case usbAudioModeChanged(USBAudioMode)
    case usbSampleRateChanged(USBSampleRate)
    case hfpBatteryChanged(Bool)
    case debugModeChanged(Bool)
    case allPairingsDeleted
    case wipeConfirmationPrompt
    case slotAlreadyConnected(Int)
    case slotSwitching(Int)
    case slotDialing(Int)
    case connectedEvent
    case disconnectedEvent
}
