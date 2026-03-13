import Foundation

/// Low-level Unix socket connection with NDJSON framing
actor DaemonConnection {
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private var buffer = Data()
    private var isOpen = false

    private let socketPath: String

    init() {
        let uid = getuid()
        self.socketPath = "/tmp/parallax-\(uid).sock"
    }

    func connect() async throws {
        let socket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socket >= 0 else {
            throw DaemonError.connectionFailed("Failed to create socket")
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let bound = ptr.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
                pathBytes.withUnsafeBufferPointer { src in
                    let count = min(src.count, 104)
                    dest.update(from: src.baseAddress!, count: count)
                    return count
                }
            }
        }

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Foundation.connect(socket, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard result == 0 else {
            close(socket)
            throw DaemonError.connectionFailed("Failed to connect: \(String(cString: strerror(errno)))")
        }

        // Create streams from file descriptor
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocket(kCFAllocatorDefault, Int32(socket), &readStream, &writeStream)

        guard let input = readStream?.takeRetainedValue() as InputStream?,
              let output = writeStream?.takeRetainedValue() as OutputStream? else {
            close(socket)
            throw DaemonError.connectionFailed("Failed to create streams")
        }

        self.inputStream = input
        self.outputStream = output

        input.open()
        output.open()
        isOpen = true
    }

    func disconnect() {
        inputStream?.close()
        outputStream?.close()
        inputStream = nil
        outputStream = nil
        isOpen = false
    }

    /// Send a JSON-RPC request and receive the response
    func sendRequest(_ request: JsonRpcRequest) async throws -> JsonRpcResponse {
        guard isOpen, let output = outputStream else {
            throw DaemonError.notConnected
        }

        let data = try JSONEncoder().encode(request)
        var line = data
        line.append(0x0A) // newline

        let written = line.withUnsafeBytes { bytes in
            output.write(bytes.bindMemory(to: UInt8.self).baseAddress!, maxLength: line.count)
        }

        guard written == line.count else {
            throw DaemonError.writeFailed
        }

        return try await readResponse()
    }

    /// Read the next line (NDJSON) from the stream
    private func readResponse() async throws -> JsonRpcResponse {
        guard let input = inputStream else {
            throw DaemonError.notConnected
        }

        while true {
            // Check if we already have a complete line in the buffer
            if let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[buffer.startIndex..<newlineIndex]
                buffer = Data(buffer[(newlineIndex + 1)...])
                let response = try JSONDecoder().decode(JsonRpcResponse.self, from: Data(lineData))
                return response
            }

            // Read more data
            var readBuffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = input.read(&readBuffer, maxLength: readBuffer.count)
            if bytesRead <= 0 {
                throw DaemonError.connectionClosed
            }
            buffer.append(contentsOf: readBuffer[0..<bytesRead])
        }
    }

    /// Read the next notification (non-response) from the stream
    func readNotification() async throws -> JsonRpcNotification {
        guard let input = inputStream else {
            throw DaemonError.notConnected
        }

        while true {
            if let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[buffer.startIndex..<newlineIndex]
                buffer = Data(buffer[(newlineIndex + 1)...])
                let notification = try JSONDecoder().decode(JsonRpcNotification.self, from: Data(lineData))
                return notification
            }

            var readBuffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = input.read(&readBuffer, maxLength: readBuffer.count)
            if bytesRead <= 0 {
                throw DaemonError.connectionClosed
            }
            buffer.append(contentsOf: readBuffer[0..<bytesRead])
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
