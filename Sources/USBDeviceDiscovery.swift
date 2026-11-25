import Foundation
import IOKit
import IOKit.serial

enum USBDeviceDiscovery {
    static let usbPodsVendorID = 0xCAFE // 51966

    static func discoverPorts() -> [SerialPortCandidate] {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching(kIOSerialBSDServiceValue) else {
            return fallbackModemPorts()
        }

        let kernResult = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kernResult == KERN_SUCCESS else {
            return fallbackModemPorts()
        }
        defer { IOObjectRelease(iterator) }

        var candidates: [SerialPortCandidate] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            guard let calloutRef = IORegistryEntryCreateCFProperty(
                service,
                kIOCalloutDeviceKey as CFString,
                kCFAllocatorDefault,
                0
            ) else {
                continue
            }
            let calloutValue = calloutRef.takeRetainedValue()
            guard let path = calloutValue as? String else { continue }

            // Filter to USB modems / serial adapters so Bluetooth incoming ports don't clutter the list
            let isUSBSerial = path.contains("usbmodem") || path.contains("usbserial")
            let vid = ancestorIntProperty(entry: service, keys: ["idVendor"])
            let pid = ancestorIntProperty(entry: service, keys: ["idProduct"])
            let product = ancestorStringProperty(entry: service, keys: ["USB Product Name", "kUSBProductString"])
            let serial = ancestorStringProperty(entry: service, keys: ["USB Serial Number", "kUSBSerialNumberString"])

            let isUSBPods = (vid == usbPodsVendorID) || (product?.localizedCaseInsensitiveContains("USBPods") == true)
            guard isUSBPods || isUSBSerial else { continue }

            candidates.append(
                SerialPortCandidate(
                    path: path,
                    productName: product,
                    vendorID: vid,
                    productID: pid,
                    serialNumber: serial,
                    isUSBPods: isUSBPods
                )
            )
        }

        if candidates.isEmpty {
            return fallbackModemPorts()
        }

        return candidates.sorted { lhs, rhs in
            if lhs.isUSBPods != rhs.isUSBPods {
                return lhs.isUSBPods && !rhs.isUSBPods
            }
            return lhs.path < rhs.path
        }
    }

    private static func fallbackModemPorts() -> [SerialPortCandidate] {
        let devDir = "/dev"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: devDir) else {
            return []
        }
        return entries
            .filter { $0.hasPrefix("cu.usbmodem") || $0.hasPrefix("cu.usbserial") }
            .sorted()
            .map {
                SerialPortCandidate(
                    path: "/dev/\($0)",
                    productName: nil,
                    vendorID: nil,
                    productID: nil,
                    serialNumber: nil,
                    isUSBPods: false
                )
            }
    }

    private static func ancestorIntProperty(entry: io_registry_entry_t, keys: [String]) -> Int? {
        let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        for key in keys {
            if let ref = IORegistryEntrySearchCFProperty(
                entry,
                kIOServicePlane,
                key as CFString,
                kCFAllocatorDefault,
                options
            ) {
                if let num = ref as? NSNumber {
                    return num.intValue
                }
            }
        }
        return nil
    }

    private static func ancestorStringProperty(entry: io_registry_entry_t, keys: [String]) -> String? {
        let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        for key in keys {
            if let ref = IORegistryEntrySearchCFProperty(
                entry,
                kIOServicePlane,
                key as CFString,
                kCFAllocatorDefault,
                options
            ) {
                if let str = ref as? String, !str.isEmpty {
                    return str
                }
            }
        }
        return nil
    }
}
