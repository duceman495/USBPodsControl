import Foundation
import CoreAudio

enum CoreAudioHelper {
    static func currentStatus() -> AudioOutputStatus {
        let devices = allOutputDevices()
        let defaultID = defaultOutputDeviceID()
        let defaultName = defaultID.flatMap { deviceName($0) }
        let usbPods = devices.first { $0.name.localizedCaseInsensitiveContains("USBPods") }

        var status = AudioOutputStatus()
        if let found = usbPods {
            status.usbPodsDeviceFound = true
            status.usbPodsDeviceName = found.name
            status.isUSBPodsDefault = (defaultID == found.id)
        }
        status.defaultOutputName = defaultName
        return status
    }

    @discardableResult
    static func switchToUSBPodsOutput() -> Bool {
        let devices = allOutputDevices()
        guard let target = devices.first(where: { $0.name.localizedCaseInsensitiveContains("USBPods") }) else {
            return false
        }
        var deviceID = target.id
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            size,
            &deviceID
        )
        return status == noErr
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        return status == noErr ? deviceID : nil
    }

    private static func allOutputDevices() -> [(id: AudioDeviceID, name: String)] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr, dataSize > 0 else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else {
            return []
        }

        var result: [(id: AudioDeviceID, name: String)] = []
        for id in deviceIDs where hasOutputStreams(id) {
            if let name = deviceName(id) {
                result.append((id: id, name: name))
            }
        }
        return result
    }

    private static func hasOutputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr,
              dataSize >= UInt32(MemoryLayout<AudioBufferList>.size) else {
            return false
        }

        let rawPtr = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPtr.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, rawPtr) == noErr else {
            return false
        }

        let bufferList = UnsafeMutableAudioBufferListPointer(rawPtr.assumingMemoryBound(to: AudioBufferList.self))
        var channels: UInt32 = 0
        for buf in bufferList {
            channels += buf.mNumberChannels
        }
        return channels > 0
    }

    private static func deviceName(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfStr: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &cfStr)
        guard status == noErr, let unmanaged = cfStr else {
            return nil
        }
        return unmanaged.takeRetainedValue() as String
    }
}
