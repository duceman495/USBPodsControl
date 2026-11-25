import Foundation
import Darwin

final class SerialPort {
    enum SerialError: LocalizedError {
        case openFailed(String, Int32)
        case configFailed(String, Int32)

        var errorDescription: String? {
            switch self {
            case let .openFailed(path, code):
                return "无法打开串口 \(path): \(String(cString: strerror(code))) (\(code))"
            case let .configFailed(msg, code):
                return "串口配置失败 (\(msg)): \(String(cString: strerror(code))) (\(code))"
            }
        }
    }

    let path: String
    private var fd: Int32 = -1
    private let queue = DispatchQueue(label: "com.usbpods.control.serial", qos: .userInitiated)
    private var readSource: DispatchSourceRead?
    private var receiveBuffer = Data()
    private var closed = false

    var onLine: ((String) -> Void)?
    var onDisconnect: ((String?) -> Void)?

    var isOpen: Bool { fd >= 0 && !closed }

    init(path: String) {
        self.path = path
    }

    deinit {
        close()
    }

    func openPort() throws {
        let openedFd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard openedFd >= 0 else {
            throw SerialError.openFailed(path, errno)
        }

        var attrs = termios()
        guard tcgetattr(openedFd, &attrs) == 0 else {
            let err = errno
            Darwin.close(openedFd)
            throw SerialError.configFailed("tcgetattr", err)
        }

        cfmakeraw(&attrs)
        cfsetispeed(&attrs, speed_t(B115200))
        cfsetospeed(&attrs, speed_t(B115200))
        attrs.c_cflag |= tcflag_t(CS8 | CREAD | CLOCAL)
        attrs.c_cflag &= ~tcflag_t(PARENB | CSTOPB | CRTSCTS)
        attrs.c_cc.16 = 1 // VMIN
        attrs.c_cc.17 = 0 // VTIME

        guard tcsetattr(openedFd, TCSANOW, &attrs) == 0 else {
            let err = errno
            Darwin.close(openedFd)
            throw SerialError.configFailed("tcsetattr", err)
        }

        // Assert DTR and RTS so TinyUSB CDC host-connected detection wakes up cleanly
        var modemFlags: Int32 = 0
        if ioctl(openedFd, UInt(TIOCMGET), &modemFlags) == 0 {
            modemFlags |= (TIOCM_DTR | TIOCM_RTS)
            _ = ioctl(openedFd, UInt(TIOCMSET), &modemFlags)
        }

        self.fd = openedFd
        self.closed = false

        let source = DispatchSource.makeReadSource(fileDescriptor: openedFd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.handleReadEvent()
        }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fd >= 0 {
                Darwin.close(self.fd)
                self.fd = -1
            }
        }
        self.readSource = source
        source.resume()
    }

    func writeString(_ text: String) {
        guard let data = text.data(using: .utf8), !data.isEmpty else { return }
        writeData(data)
    }

    func writeData(_ data: Data) {
        queue.async { [weak self] in
            guard let self, self.fd >= 0, !self.closed else { return }
            data.withUnsafeBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress else { return }
                var offset = 0
                let total = data.count
                var retries = 0
                while offset < total && retries < 20 {
                    let written = Darwin.write(self.fd, base.advanced(by: offset), total - offset)
                    if written > 0 {
                        offset += written
                    } else if written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                        retries += 1
                        usleep(2_000)
                    } else {
                        self.handleRemoteDisconnect(reason: "串口写入失败: \(String(cString: strerror(errno)))")
                        return
                    }
                }
            }
        }
    }

    func close() {
        queue.sync {
            guard !closed else { return }
            closed = true
            if let source = readSource {
                readSource = nil
                source.cancel()
            } else if fd >= 0 {
                Darwin.close(fd)
                fd = -1
            }
            receiveBuffer.removeAll()
        }
    }

    private func handleReadEvent() {
        guard fd >= 0, !closed else { return }
        var temp = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fd, &temp, temp.count)
            if count > 0 {
                receiveBuffer.append(temp, count: count)
                drainLines()
            } else if count == 0 {
                let exists = Darwin.access(path, F_OK) == 0
                var modem: Int32 = 0
                let ioctlOK = ioctl(fd, UInt(TIOCMGET), &modem) == 0
                if exists && ioctlOK {
                    break
                }
                handleRemoteDisconnect(reason: nil)
                return
            } else {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    break
                }
                handleRemoteDisconnect(reason: String(cString: strerror(errno)))
                return
            }
        }
    }

    private func drainLines() {
        let newline = UInt8(ascii: "\n")
        let carriageReturn = UInt8(ascii: "\r")

        while let idx = receiveBuffer.firstIndex(of: newline) {
            let lineData = receiveBuffer.subdata(in: 0..<idx)
            receiveBuffer.removeSubrange(0...idx)

            let cleaned = Data(lineData.filter { $0 != carriageReturn })
            let line = String(decoding: cleaned, as: UTF8.self)
            onLine?(line)
        }

        // Flush interactive prompts without trailing newline (e.g. "[y/N] ")
        if !receiveBuffer.isEmpty {
            let cleaned = Data(receiveBuffer.filter { $0 != carriageReturn })
            let partial = String(decoding: cleaned, as: UTF8.self)
            if partial.contains("[y/N]") {
                receiveBuffer.removeAll()
                onLine?(partial)
            }
        }
    }

    private func handleRemoteDisconnect(reason: String?) {
        guard !closed else { return }
        closed = true
        if let source = readSource {
            readSource = nil
            source.cancel()
        } else if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
        onDisconnect?(reason)
    }
}
