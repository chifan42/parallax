import Foundation

/// Low-level Unix socket connection with NDJSON framing
/// Uses a background read loop to dispatch responses and notifications
class DaemonConnection: @unchecked Sendable {
    private var fileDescriptor: Int32 = -1
    private var readFD: Int32 = -1
    private var writeFD: Int32 = -1

    private let socketPath: String
    private var isOpen = false

    // Pending request continuations keyed by JSON-RPC id string
    private let lock = NSLock()
    private var pending: [String: CheckedContinuation<JsonRpcResponse, Error>] = [:]
    private var notificationHandler: ((JsonRpcNotification) -> Void)?
    private var readTask: Task<Void, Never>?

    init() {
        let uid = getuid()
        self.socketPath = "/tmp/parallax-\(uid).sock"
    }

    func connect() async throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw DaemonError.connectionFailed("Failed to create socket")
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            _ = ptr.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
                pathBytes.withUnsafeBufferPointer { src in
                    let count = min(src.count, 104)
                    dest.update(from: src.baseAddress!, count: count)
                    return count
                }
            }
        }

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Foundation.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard result == 0 else {
            close(fd)
            throw DaemonError.connectionFailed("Failed to connect: \(String(cString: strerror(errno)))")
        }

        self.fileDescriptor = fd
        // Duplicate fd so read and write don't interfere
        self.readFD = dup(fd)
        self.writeFD = fd
        self.isOpen = true

        // Start background read loop
        startReadLoop()
    }

    func disconnect() {
        isOpen = false
        readTask?.cancel()
        if readFD >= 0 { close(readFD); readFD = -1 }
        if writeFD >= 0 { close(writeFD); writeFD = -1 }
        fileDescriptor = -1

        // Fail all pending requests
        lock.lock()
        let waiters = pending
        pending.removeAll()
        lock.unlock()
        for (_, cont) in waiters {
            cont.resume(throwing: DaemonError.connectionClosed)
        }
    }

    func setNotificationHandler(_ handler: @escaping (JsonRpcNotification) -> Void) {
        lock.lock()
        notificationHandler = handler
        lock.unlock()
    }

    /// Send a JSON-RPC request and await the response
    func sendRequest(_ request: JsonRpcRequest) async throws -> JsonRpcResponse {
        guard isOpen else { throw DaemonError.notConnected }

        let requestKey: String
        switch request.id {
        case .string(let s): requestKey = s
        case .number(let n): requestKey = String(n)
        case nil: requestKey = "unknown"
        }

        // Write the request
        let data = try JSONEncoder().encode(request)
        var line = data
        line.append(0x0A) // newline

        let written = line.withUnsafeBytes { bytes in
            Darwin.write(writeFD, bytes.baseAddress!, line.count)
        }
        guard written == line.count else {
            throw DaemonError.writeFailed
        }

        // Wait for the response via continuation
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            pending[requestKey] = continuation
            lock.unlock()
        }
    }

    // MARK: - Background read loop

    private func startReadLoop() {
        readTask = Task.detached { [weak self] in
            guard let self else { return }
            var buffer = Data()
            var readBuffer = [UInt8](repeating: 0, count: 8192)

            while self.isOpen && !Task.isCancelled {
                let bytesRead = Darwin.read(self.readFD, &readBuffer, readBuffer.count)
                if bytesRead <= 0 {
                    // Connection closed or error
                    self.isOpen = false
                    self.lock.lock()
                    let waiters = self.pending
                    self.pending.removeAll()
                    self.lock.unlock()
                    for (_, cont) in waiters {
                        cont.resume(throwing: DaemonError.connectionClosed)
                    }
                    break
                }

                buffer.append(contentsOf: readBuffer[0..<bytesRead])

                // Process complete lines
                while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                    let lineData = Data(buffer[buffer.startIndex..<newlineIndex])
                    buffer = Data(buffer[(newlineIndex + 1)...])

                    self.dispatchLine(lineData)
                }
            }
        }
    }

    private func dispatchLine(_ data: Data) {
        // Try to parse as a response (has "id" field)
        // or as a notification (has "method" but no "id")
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if json["id"] != nil {
            // It's a response — resume the pending continuation
            if let response = try? JSONDecoder().decode(JsonRpcResponse.self, from: data) {
                let key: String
                switch response.id {
                case .string(let s): key = s
                case .number(let n): key = String(n)
                case nil: key = "unknown"
                }
                lock.lock()
                let continuation = pending.removeValue(forKey: key)
                lock.unlock()
                continuation?.resume(returning: response)
            }
        } else if json["method"] != nil {
            // It's a notification
            if let notification = try? JSONDecoder().decode(JsonRpcNotification.self, from: data) {
                lock.lock()
                let handler = notificationHandler
                lock.unlock()
                handler?(notification)
            }
        }
    }

    var connected: Bool { isOpen }
}

enum DaemonError: Error, LocalizedError {
    case connectionFailed(String)
    case notConnected
    case writeFailed
    case connectionClosed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .notConnected: return "Not connected to daemon"
        case .writeFailed: return "Failed to write to daemon"
        case .connectionClosed: return "Connection closed"
        case .invalidResponse: return "Invalid response from daemon"
        }
    }
}
