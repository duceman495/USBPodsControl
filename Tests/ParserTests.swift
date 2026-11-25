import Foundation

func check(_ condition: Bool, _ message: String) {
    if !condition {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func feedLines(_ lines: [String], into parser: USBPodsParser, initial: USBPodsState = USBPodsState()) -> [USBPodsEvent] {
    var state = initial
    var out: [USBPodsEvent] = []
    for line in lines {
        let events = parser.feed(line: line, currentState: state)
        for ev in events {
            if case let .menuSnapshot(snap) = ev {
                state = snap
            }
            out.append(ev)
        }
    }
    return out
}

func testDisconnectedMenu() {
    let sample = """
    =============  USBPods Lite  Ver. 1.0.2  =============
     Not connected — press c to connect, or p to pair new earbuds
    -----------------------------------------------------
     Music      ,  next        .  previous    /  play-pause
     Volume     [  up          ]  down
    -----------------------------------------------------
     Earbuds    c  connect     d  disconnect  p  pair NEW earbuds
                1  (empty — press p to pair)   <- current
                2  (empty — press p to pair)
                press 1 or 2 to change slot
                l  all saved devices          r  forget everything
    -----------------------------------------------------
     Settings   w  auto-connect on power ....... ON
                z  pause PC when headset drops .. ON
                u  USB audio mode .............. UAC2
                k  USB sample rate ............. 48 kHz
                b  earbud button ............... volume up (short) / down (long)
                q  LDAC quality ................ 660 kbps
                e  LHDC bitrate ................ 400 kbps
     Codecs     5  AAC-ELD (AirPods) ........... ON
                6  LHDC V5 ..................... ON
                7  LDAC ........................ ON
                8  AAC ......................... ON
    -----------------------------------------------------
     h  show this menu   H  advanced menu   D  debug mode
    =====================================================
    """.components(separatedBy: "\n")

    let parser = USBPodsParser()
    let events = feedLines(sample, into: parser)
    guard case let .menuSnapshot(s)? = events.last else {
        check(false, "Expected menuSnapshot for disconnected menu")
        return
    }
    check(s.variant == "USBPods Lite", "variant mismatch: \(s.variant)")
    check(s.firmwareVersion == "1.0.2", "version mismatch: \(s.firmwareVersion)")
    check(!s.isConnected, "should be disconnected")
    check(s.currentSlot == 1, "currentSlot should be 1")
    check(s.slot1.isEmpty && s.slot2.isEmpty, "both slots should be empty")
    check(s.autoConnectOnPower && s.pauseOnDisconnect, "w and z should be ON")
    check(s.usbAudioMode == .uac2 && s.usbSampleRate == .khz48, "UAC2 48kHz expected")
    check(s.earbudButtonMode == .volume, "button mode expected .volume")
    check(s.ldacQualityKbps == 660 && s.lhdcBitrateKbps == 400, "660/400 expected")
    check(s.codecAacEldEnabled && s.codecLhdcEnabled && s.codecLdacEnabled && s.codecAacEnabled, "all codecs ON")
}

func testConnectedLDACAndBatteriesMenu() {
    let sample = """
    =============  USBPods Lite  Ver. 1.0.2  =============
     Connected: WH-1000XM5   (playing)
                LDAC  990 kbps   batt 85%   L 80%+   R 90%   case 100%+
    -----------------------------------------------------
     Earbuds    c  connect     d  disconnect  p  pair NEW earbuds
                1  WH-1000XM5
                2  AirPods Pro   <- current
                press 1 or 2 to change slot
    -----------------------------------------------------
     Settings   w  auto-connect on power ....... off
                z  pause PC when headset drops .. off
                u  USB audio mode .............. UAC1 (legacy hosts)
                k  USB sample rate ............. 44.1 kHz
                b  earbud button ............... play / pause
                q  LDAC quality ................ 990 kbps
                e  LHDC bitrate ................ 900 kbps
     Codecs     5  AAC-ELD (AirPods) ........... off
                6  LHDC V5 ..................... off
                7  LDAC ........................ ON
                8  AAC ......................... off
    -----------------------------------------------------
    =====================================================
    """.components(separatedBy: "\n")

    let parser = USBPodsParser()
    let events = feedLines(sample, into: parser)
    guard case let .menuSnapshot(s)? = events.last else {
        check(false, "Expected menuSnapshot for connected menu")
        return
    }
    check(s.isConnected && s.isPlaying, "should be connected and playing")
    check(s.connectedDeviceName == "WH-1000XM5", "device name mismatch: \(String(describing: s.connectedDeviceName))")
    check(s.activeCodec == "LDAC", "codec mismatch: \(String(describing: s.activeCodec))")
    check(s.activeBitrateKbps == 990, "bitrate mismatch")
    check(s.hfpBatteryPercent == 85, "hfp batt mismatch")
    check(s.leftBattery == BatteryLevel(percent: 80, charging: true), "left battery mismatch")
    check(s.rightBattery == BatteryLevel(percent: 90, charging: false), "right battery mismatch")
    check(s.caseBattery == BatteryLevel(percent: 100, charging: true), "case battery mismatch")
    check(s.currentSlot == 2, "slot 2 should be current")
    check(!s.slot1.isEmpty && s.slot1.label == "WH-1000XM5", "slot 1 label mismatch")
    check(!s.slot2.isEmpty && s.slot2.label == "AirPods Pro", "slot 2 label mismatch")
    check(!s.autoConnectOnPower && !s.pauseOnDisconnect, "w and z should be off")
    check(s.usbAudioMode == .uac1 && s.usbSampleRate == .khz44_1, "UAC1 44.1kHz expected")
    check(s.earbudButtonMode == .playPause, "button mode expected playPause")
    check(s.ldacQualityKbps == 990 && s.lhdcBitrateKbps == 900, "990/900 expected")
    check(!s.codecAacEldEnabled && !s.codecLhdcEnabled && s.codecLdacEnabled && !s.codecAacEnabled, "only LDAC ON")
}

func testAacEldNotConfusedWithAac() {
    let sample = """
    ===============  USBPods  Ver. 1.0.2  ===============
     Connected: AirPods Pro 2
                AAC-ELD  256 kbps   L 95%   R 95%
    =====================================================
    """.components(separatedBy: "\n")

    let parser = USBPodsParser()
    let events = feedLines(sample, into: parser)
    guard case let .menuSnapshot(s)? = events.last else {
        check(false, "Expected menuSnapshot for AAC-ELD")
        return
    }
    check(s.variant == "USBPods", "variant mismatch")
    check(s.activeCodec == "AAC-ELD", "should match AAC-ELD, got \(String(describing: s.activeCodec))")
    check(s.activeBitrateKbps == 256, "AAC-ELD bitrate mismatch")
    check(!s.isPlaying, "should not be playing")
}

func testLiveEventsAndAdvancedMenu() {
    let lines = [
        "pairing into slot 2 — scanning",
        "LDAC quality: 990 kbps",
        "LHDC bitrate: 500 kbps",
        "earbud button: restart the audio stream",
        "AAC-ELD: disabled (applies at the next connection)",
        "LDAC: enabled (applies at the next connection)",
        "auto-connect on power: off",
        "pause PC when headset drops: ON",
        "USB audio mode: UAC1 (replug USB to apply)",
        "USB sample rate: 44.1 kHz (replug USB to apply)",
        "--- USBPods advanced (debug mode ON) ---",
        "hfp     Y HFP battery SLC ....... ON  (saved; reboot to apply)",
        "Delete ALL pairings (link keys + slots 1 and 2)? [y/N] ",
        "all pairings deleted — 'p' to pair again"
    ]

    let parser = USBPodsParser()
    let events = feedLines(lines, into: parser)
    check(events.contains(.scanningStarted(slot: 2)), "scanningStarted(2) missing")
    check(events.contains(.ldacQualityChanged(kbps: 990)), "ldac 990 missing")
    check(events.contains(.lhdcBitrateChanged(kbps: 500)), "lhdc 500 missing")
    check(events.contains(.earbudButtonChanged(.restartStream)), "earbudButton restartStream missing")
    check(events.contains(.codecToggled(name: "AAC-ELD", enabled: false)), "AAC-ELD disabled missing")
    check(events.contains(.codecToggled(name: "LDAC", enabled: true)), "LDAC enabled missing")
    check(events.contains(.autoConnectChanged(false)), "autoConnect false missing")
    check(events.contains(.pauseOnDisconnectChanged(true)), "pauseOnDisconnect true missing")
    check(events.contains(.usbAudioModeChanged(.uac1)), "usbAudioMode uac1 missing")
    check(events.contains(.usbSampleRateChanged(.khz44_1)), "usbSampleRate 44.1 missing")
    check(events.contains(.debugModeChanged(true)), "debugMode true missing")
    check(events.contains(.hfpBatteryChanged(true)), "hfpBattery true missing")
    check(events.contains(.wipeConfirmationPrompt), "wipeConfirmationPrompt missing")
    check(events.contains(.allPairingsDeleted), "allPairingsDeleted missing")
}

@main
struct ParserTestRunner {
    static func main() {
        testDisconnectedMenu()
        testConnectedLDACAndBatteriesMenu()
        testAacEldNotConfusedWithAac()
        testLiveEventsAndAdvancedMenu()
        print("ALL PARSER TESTS PASSED")
    }
}
