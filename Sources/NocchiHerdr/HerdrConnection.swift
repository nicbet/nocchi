import Darwin
import Foundation
import Synchronization

/// One blocking Unix-socket connection to Herdr that reads NDJSON lines.
///
/// Lines are split on raw bytes and only complete lines are decoded, so a multi-byte UTF-8
/// character split across two reads stays intact. Calls block; `HerdrClient` runs them off the
/// cooperative thread pool.
final class HerdrConnection: Sendable {
    /// Snapshots of a busy session are large.
    static let maxLineLength = 16 << 20

    private let fd: Int32
    private let isClosed = Mutex(false)
    /// Bytes read past the last returned line. Only the reading thread touches it.
    private let pending = Mutex(Data())

    /// Connects to `path`. With a `timeout`, reads and writes that take longer throw `.timeout`.
    init(path: String, timeout: Duration?) throws {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else {
            throw HerdrError.unavailable("socket path is longer than \(capacity - 1) bytes: \(path)")
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw HerdrError.unavailable("socket(): \(String(cString: strerror(errno)))") }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: path.utf8)
            raw[path.utf8.count] = 0
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            let code = errno
            Darwin.close(fd)
            switch code {
            case ENOENT, ECONNREFUSED: throw HerdrError.unavailable("Herdr isn't running")
            default: throw HerdrError.unavailable("connect: \(String(cString: strerror(code)))")
            }
        }
        self.fd = fd
        setTimeout(timeout)
    }

    /// Wraps an already connected socket (tests use a socket pair).
    init(fileDescriptor fd: Int32) {
        self.fd = fd
    }

    deinit { Darwin.close(fd) }

    /// Read and write timeout; `nil` waits forever.
    func setTimeout(_ timeout: Duration?) {
        let (seconds, attoseconds) = (timeout ?? .zero).components
        var value = timeval(tv_sec: Int(seconds), tv_usec: Int32(attoseconds / 1_000_000_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
    }

    func write(_ data: Data) throws {
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw errno == EAGAIN ? HerdrError.timeout : HerdrError.unavailable("write: \(String(cString: strerror(errno)))")
                }
                offset += n
            }
        }
    }

    /// The next line without its newline, or `nil` at end of stream.
    func readLine() throws -> Data? {
        try pending.withLock { buffer in
            var searchFrom = buffer.startIndex
            var chunk = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                if let newline = buffer[searchFrom...].firstIndex(of: 0x0A) {
                    let line = Data(buffer[buffer.startIndex..<newline])
                    buffer = Data(buffer[(newline + 1)...])
                    return line
                }
                searchFrom = buffer.endIndex
                guard buffer.count <= Self.maxLineLength else {
                    throw HerdrError.badResponse("line longer than \(Self.maxLineLength) bytes")
                }
                let n = chunk.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, $0.count) }
                if n > 0 {
                    buffer.append(contentsOf: chunk[0..<n])
                } else if n == 0 || isClosed.withLock({ $0 }) {
                    return nil
                } else if errno == EINTR {
                    continue
                } else if errno == EAGAIN {
                    throw HerdrError.timeout
                } else {
                    throw HerdrError.unavailable("read: \(String(cString: strerror(errno)))")
                }
            }
        }
    }

    /// Wakes a blocked reader (it sees end of stream). The descriptor closes on deinit, once the
    /// reader has let go of the connection.
    func close() {
        let first = isClosed.withLock { closed in
            defer { closed = true }
            return !closed
        }
        if first { shutdown(fd, SHUT_RDWR) }
    }
}
