import Darwin
import Foundation
import NocchiHookProtocol
import Synchronization

/// Listens on nocchi's hook socket and streams what `nocchi-hook` sends. One server per app; the
/// native adapters each take the messages for their agent from `messages(for:)`.
public final class HookServer: Sendable {
    public let path: String
    private let state = Mutex(State())

    private struct State {
        var fd: Int32 = -1
        var subscribers: [UUID: (agent: String, continuation: AsyncStream<HookMessage>.Continuation)] = [:]
    }

    public init(path: String = HookMessage.socketPath()) {
        self.path = path
    }

    /// Starts listening. A leftover socket file from a previous run is replaced.
    public func start() throws {
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: path.utf8)
            raw[path.utf8.count] = 0
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 64) == 0 else {
            let code = errno
            close(fd)
            throw POSIXError(.init(rawValue: code) ?? .EIO)
        }
        chmod(path, 0o600)
        state.withLock { $0.fd = fd }

        let thread = Thread { [self] in acceptLoop(fd) }
        thread.name = "nocchi.hooks"
        thread.start()
    }

    public func stop() {
        let (fd, subscribers) = state.withLock { state in
            defer { state.fd = -1; state.subscribers = [:] }
            return (state.fd, state.subscribers)
        }
        if fd >= 0 {
            shutdown(fd, SHUT_RDWR)
            close(fd)
            unlink(path)
        }
        for subscriber in subscribers.values { subscriber.continuation.finish() }
    }

    /// Messages from `agent`'s hooks ("claude", "codex") from now on.
    public func messages(for agent: String) -> AsyncStream<HookMessage> {
        let (stream, continuation) = AsyncStream.makeStream(of: HookMessage.self)
        let id = UUID()
        state.withLock { $0.subscribers[id] = (agent, continuation) }
        continuation.onTermination = { [weak self] _ in
            _ = self?.state.withLock { $0.subscribers.removeValue(forKey: id) }
        }
        return stream
    }

    private func acceptLoop(_ listener: Int32) {
        while true {
            let client = accept(listener, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return  // stopped
            }
            DispatchQueue.global(qos: .utility).async { [self] in handle(client) }
        }
    }

    private func handle(_ client: Int32) {
        defer { close(client) }
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while data.count < 1 << 20 {
            let n = buffer.withUnsafeMutableBytes { read(client, $0.baseAddress!, $0.count) }
            if n <= 0 { break }
            data.append(contentsOf: buffer[0..<n])
            if data.last == 0x0A { break }
        }
        guard let message = try? JSONDecoder().decode(HookMessage.self, from: data),
              message.version == HookMessage.currentVersion else { return }
        let targets = state.withLock { $0.subscribers.values.filter { $0.agent == message.agent }.map(\.continuation) }
        for continuation in targets { continuation.yield(message) }
    }
}
