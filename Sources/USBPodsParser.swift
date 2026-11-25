import Foundation

final class USBPodsParser {
    private var isCapturingMenu = false
    private var draftState: USBPodsState
    private var expectingDetailLine = false

    init(initialState: USBPodsState = USBPodsState()) {
        self.draftState = initialState
    }

    func feed(line rawLine: String, currentState: USBPodsState) -> [USBPodsEvent] {
        let line = rawLine.replacingOccurrences(of: "\r", with: "")
        var events: [USBPodsEvent] = []

        if let header = parseMenuHeader(line) {
            isCapturingMenu = true
            expectingDetailLine = false
            draftState = currentState
            draftState.variant = header.variant
            draftState.firmwareVersion = header.version
            return events
        }

        if isCapturingMenu {
            if isMenuFooter(line) {
                isCapturingMenu = false
                expectingDetailLine = false
                events.append(.menuSnapshot(draftState))
                return events
            }
            parseMenuLine(line)
            return events
        }

        if let event = parseSingleLineEvent(line) {
            events.append(event)
        }
        return events
    }

    // MARK: - Menu Block Parsing

    private func parseMenuHeader(_ line: String) -> (variant: String, version: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("===="), trimmed.hasSuffix("===="), trimmed.contains("Ver.") else {
            return nil
        }
        let inner = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "= "))
        guard let verRange = inner.range(of: "Ver.") else { return nil }
        let variant = inner[..<verRange.lowerBound].trimmingCharacters(in: .whitespaces)
        let version = inner[verRange.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !variant.isEmpty, !version.isEmpty else { return nil }
        return (variant, version)
    }

    private func isMenuFooter(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 20 && trimmed.allSatisfy { $0 == "=" }
    }

    private func parseMenuLine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if line.hasPrefix(" Connected:") {
            draftState.isConnected = true
            draftState.isScanning = false
            var rest = String(line.dropFirst(" Connected:".count)).trimmingCharacters(in: .whitespaces)
            if rest.hasSuffix("(playing)") {
                draftState.isPlaying = true
                rest = String(rest.dropLast("(playing)".count)).trimmingCharacters(in: .whitespaces)
            } else {
                draftState.isPlaying = false
            }
            draftState.connectedDeviceName = rest.isEmpty ? nil : rest
            draftState.activeCodec = nil
            draftState.activeBitrateKbps = nil
            draftState.hfpBatteryPercent = nil
            draftState.leftBattery = nil
            draftState.rightBattery = nil
            draftState.caseBattery = nil
            expectingDetailLine = true
            return
        }

        if expectingDetailLine {
            expectingDetailLine = false
            if !trimmed.hasPrefix("---") && !trimmed.isEmpty && line.hasPrefix("           ") {
                parseConnectedDetailsLine(trimmed, into: &draftState)
                return
            }
        }

        if line.hasPrefix(" Not connected") {
            draftState.isConnected = false
            draftState.isPlaying = false
            draftState.connectedDeviceName = nil
            draftState.activeCodec = nil
            draftState.activeBitrateKbps = nil
            draftState.hfpBatteryPercent = nil
            draftState.leftBattery = nil
            draftState.rightBattery = nil
            draftState.caseBattery = nil
            expectingDetailLine = false
            return
        }

        if let slot = parseSlotLine(trimmed) {
            if slot.info.number == 1 {
                draftState.slot1 = slot.info
            } else if slot.info.number == 2 {
                draftState.slot2 = slot.info
            }
            if slot.isCurrent {
                draftState.currentSlot = slot.info.number
            }
            return
        }

        if let val = extractSettingValue(trimmed, key: "w", prefix: "auto-connect on power") {
            draftState.autoConnectOnPower = (val.uppercased() == "ON")
            return
        }
        if let val = extractSettingValue(trimmed, key: "z", prefix: "pause PC when headset drops") {
            draftState.pauseOnDisconnect = (val.uppercased() == "ON")
            return
        }
        if let val = extractSettingValue(trimmed, key: "u", prefix: "USB audio mode") {
            draftState.usbAudioMode = val.uppercased().hasPrefix("UAC1") ? .uac1 : .uac2
            return
        }
        if let val = extractSettingValue(trimmed, key: "k", prefix: "USB sample rate") {
            draftState.usbSampleRate = val.contains("44.1") ? .khz44_1 : .khz48
            return
        }
        if let val = extractSettingValue(trimmed, key: "b", prefix: "earbud button") {
            if let mode = EarbudButtonMode.fromFirmwareString(val) {
                draftState.earbudButtonMode = mode
            }
            return
        }
        if let val = extractSettingValue(trimmed, key: "q", prefix: "LDAC quality") {
            if let kbps = extractFirstInt(in: val) {
                draftState.ldacQualityKbps = kbps
            }
            return
        }
        if let val = extractSettingValue(trimmed, key: "e", prefix: "LHDC bitrate") {
            if let kbps = extractFirstInt(in: val) {
                draftState.lhdcBitrateKbps = kbps
            }
            return
        }

        if let val = extractSettingValue(trimmed, key: "5", prefix: "AAC-ELD") {
            draftState.codecAacEldEnabled = (val.uppercased() == "ON")
            return
        }
        if let val = extractSettingValue(trimmed, key: "6", prefix: "LHDC V5") {
            draftState.codecLhdcEnabled = (val.uppercased() == "ON")
            return
        }
        if let val = extractSettingValue(trimmed, key: "7", prefix: "LDAC") {
            draftState.codecLdacEnabled = (val.uppercased() == "ON")
            return
        }
        if let val = extractSettingValue(trimmed, key: "8", prefix: "AAC") {
            draftState.codecAacEnabled = (val.uppercased() == "ON")
            return
        }
    }

    private func parseConnectedDetailsLine(_ line: String, into state: inout USBPodsState) {
        // Order matters: check AAC-ELD before AAC
        let codecs = ["AAC-ELD", "LDAC", "LHDC", "AAC", "SBC"]
        for codec in codecs {
            if line.range(of: "\\b\(NSRegularExpression.escapedPattern(for: codec))\\b", options: .regularExpression) != nil {
                state.activeCodec = codec
                break
            }
        }

        if let kb = matchFirstGroup(in: line, pattern: #"(\d+)\s+kbps"#), let val = Int(kb) {
            state.activeBitrateKbps = val
        }
        if let hb = matchFirstGroup(in: line, pattern: #"\bbatt\s+(\d+)%"#), let val = Int(hb) {
            state.hfpBatteryPercent = val
        }
        if let left = parseBatteryComponent(in: line, label: "L") {
            state.leftBattery = left
        }
        if let right = parseBatteryComponent(in: line, label: "R") {
            state.rightBattery = right
        }
        if let caseBat = parseBatteryComponent(in: line, label: "case") {
            state.caseBattery = caseBat
        }
    }

    private func parseBatteryComponent(in line: String, label: String) -> BatteryLevel? {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: label))\\s+(\\d+)%(\\+?)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges >= 3,
              let pctRange = Range(match.range(at: 1), in: line),
              let pct = Int(line[pctRange]) else {
            return nil
        }
        let plusRange = Range(match.range(at: 2), in: line)
        let charging = plusRange.map { !line[$0].isEmpty } ?? false
        return BatteryLevel(percent: pct, charging: charging)
    }

    private func parseSlotLine(_ trimmed: String) -> (info: SlotInfo, isCurrent: Bool)? {
        guard let first = trimmed.first, first == "1" || first == "2" else { return nil }
        let rest = String(trimmed.dropFirst())
        guard rest.hasPrefix("  ") else { return nil }

        let number = (first == "1") ? 1 : 2
        var label = rest.trimmingCharacters(in: .whitespaces)
        var isCurrent = false
        if label.hasSuffix("<- current") {
            isCurrent = true
            label = String(label.dropLast("<- current".count)).trimmingCharacters(in: .whitespaces)
        }
        let isEmpty = label.hasPrefix("(empty")
        let cleanLabel = isEmpty ? "空槽位" : label
        return (SlotInfo(number: number, label: cleanLabel, isEmpty: isEmpty), isCurrent)
    }

    private func extractSettingValue(_ trimmed: String, key: String, prefix: String) -> String? {
        // Handles both "Settings   w  auto-connect..." and "w  auto-connect..." and "Codecs     5  AAC-ELD..."
        var work = trimmed
        if work.hasPrefix("Settings") {
            work = String(work.dropFirst("Settings".count)).trimmingCharacters(in: .whitespaces)
        } else if work.hasPrefix("Codecs") {
            work = String(work.dropFirst("Codecs".count)).trimmingCharacters(in: .whitespaces)
        }

        guard work.hasPrefix("\(key)  ") else { return nil }
        let afterKey = String(work.dropFirst(key.count)).trimmingCharacters(in: .whitespaces)
        guard afterKey.hasPrefix(prefix) else { return nil }

        // Dotted leader: "....... ON" or ".. 48 kHz"
        guard let dotRange = afterKey.range(of: "..", options: .backwards) else {
            return nil
        }
        return String(afterKey[dotRange.upperBound...]).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Single-line Events & Advanced Menu

    private func parseSingleLineEvent(_ line: String) -> USBPodsEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if let slotStr = matchFirstGroup(in: trimmed, pattern: #"^pairing into slot (\d+)"#),
           let slot = Int(slotStr) {
            return .scanningStarted(slot: slot)
        }

        if let kbpsStr = matchFirstGroup(in: trimmed, pattern: #"^LDAC quality:\s*(\d+)\s*kbps$"#),
           let kbps = Int(kbpsStr) {
            return .ldacQualityChanged(kbps: kbps)
        }

        if let kbpsStr = matchFirstGroup(in: trimmed, pattern: #"^LHDC bitrate:\s*(\d+)\s*kbps$"#),
           let kbps = Int(kbpsStr) {
            return .lhdcBitrateChanged(kbps: kbps)
        }

        if trimmed.hasPrefix("earbud button:") {
            let raw = String(trimmed.dropFirst("earbud button:".count))
            if let mode = EarbudButtonMode.fromFirmwareString(raw) {
                return .earbudButtonChanged(mode)
            }
        }

        for codecName in ["AAC-ELD", "LHDC V5", "LDAC", "AAC"] {
            if trimmed.hasPrefix("\(codecName):") {
                let lower = trimmed.lowercased()
                if lower.contains("enabled") {
                    return .codecToggled(name: codecName, enabled: true)
                } else if lower.contains("disabled") {
                    return .codecToggled(name: codecName, enabled: false)
                }
            }
        }

        if trimmed.hasPrefix("auto-connect on power:") {
            let val = trimmed.dropFirst("auto-connect on power:".count).trimmingCharacters(in: .whitespaces)
            return .autoConnectChanged(val.uppercased().hasPrefix("ON"))
        }

        if trimmed.hasPrefix("pause PC when headset drops:") {
            let val = trimmed.dropFirst("pause PC when headset drops:".count).trimmingCharacters(in: .whitespaces)
            return .pauseOnDisconnectChanged(val.uppercased().hasPrefix("ON"))
        }

        if trimmed.hasPrefix("USB audio mode:") {
            let val = trimmed.dropFirst("USB audio mode:".count).trimmingCharacters(in: .whitespaces)
            return .usbAudioModeChanged(val.uppercased().contains("UAC1") ? .uac1 : .uac2)
        }

        if trimmed.hasPrefix("USB sample rate:") {
            let val = trimmed.dropFirst("USB sample rate:".count).trimmingCharacters(in: .whitespaces)
            return .usbSampleRateChanged(val.contains("44.1") ? .khz44_1 : .khz48)
        }

        if trimmed.hasPrefix("HFP battery SLC ") {
            let lower = trimmed.lowercased()
            return .hfpBatteryChanged(lower.contains("enabled"))
        }

        if trimmed.hasPrefix("[dbg] debug mode ") {
            let lower = trimmed.lowercased()
            return .debugModeChanged(lower.contains(" on"))
        }

        // Advanced menu ('H') lines
        if trimmed.hasPrefix("--- USBPods advanced (debug mode ") {
            let lower = trimmed.lowercased()
            return .debugModeChanged(lower.contains("on)"))
        }
        if trimmed.hasPrefix("hfp     Y HFP battery SLC") {
            let lower = trimmed.lowercased()
            return .hfpBatteryChanged(lower.contains("on"))
        }

        if trimmed.contains("Delete ALL pairings") && trimmed.contains("[y/N]") {
            return .wipeConfirmationPrompt
        }

        if trimmed.hasPrefix("all pairings deleted") || trimmed.hasPrefix("Deleting all link keys") {
            return .allPairingsDeleted
        }

        if let slotStr = matchFirstGroup(in: trimmed, pattern: #"^slot (\d+) is already connected$"#),
           let slot = Int(slotStr) {
            return .slotAlreadyConnected(slot)
        }

        if let slotStr = matchFirstGroup(in: trimmed, pattern: #"^slot (\d+)\s+.*dropping the current link"#),
           let slot = Int(slotStr) {
            return .slotSwitching(slot)
        }

        if let slotStr = matchFirstGroup(in: trimmed, pattern: #"^dialing slot (\d+)$"#),
           let slot = Int(slotStr) {
            return .slotDialing(slot)
        }

        // Background BTstack/AVDTP connection events that often appear in serial logs
        let lower = trimmed.lowercased()
        if lower.contains("avdtp") && (lower.contains("stream started") || lower.contains("connected") || lower.contains("configured")) {
            return .connectedEvent
        }
        if lower.contains("avdtp") && (lower.contains("disconnected") || lower.contains("released")) {
            return .disconnectedEvent
        }

        return nil
    }

    // MARK: - Helpers

    private func extractFirstInt(in text: String) -> Int? {
        guard let str = matchFirstGroup(in: text, pattern: #"(\d+)"#) else { return nil }
        return Int(str)
    }

    private func matchFirstGroup(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }
}
