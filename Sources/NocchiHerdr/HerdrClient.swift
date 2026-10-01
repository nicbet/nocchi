import Foundation
import Synchronization

/// Talks to one Herdr server. Herdr closes the socket after each reply and ignores pipelined
/// requests, so every request gets its own connection; event streams get a dedicated one each.
/// A request that was written is never resent (`agent.start` isn't idempotent).
public struct HerdrClient: Sendable {
    public let socketPath: String
    public var timeout: Duration
    /// Sees every request before it's sent. Integration tests record them for the schema check.
    public var onRequest: (@Sendable (HerdrRequest) -> Void)?

    public init(socketPath: String, timeout: Duration = .seconds(5), onRequest: (@Sendable (HerdrRequest) -> Void)? = nil) {
        self.socketPath = socketPath
        self.timeout = timeout
        self.onRequest = onRequest
    }

    private static let counter = Mutex(0)
    private static func nextID() -> String {
        "nocchi-\(counter.withLock { $0 += 1; return $0 })"
    }

    // MARK: Requests

    public struct Pong: Decodable, Sendable {
        public var version: String
        public var `protocol`: Int
    }

    public func ping() async throws -> Pong {
        try await call(.ping, as: Pong.self, timeout: .seconds(1))
    }

    public func snapshot() async throws -> HerdrSnapshot {
        struct Result: Decodable { var snapshot: HerdrSnapshot }
        return try await call(.snapshot, as: Result.self).snapshot
    }

    /// Sends `request` and decodes `result` as `R`.
    public func call<R: Decodable & Sendable>(_ request: HerdrRequest, as: R.Type, timeout: Duration? = nil) async throws -> R {
        let line = try await send(request, timeout: timeout)
        do {
            return try JSONDecoder().decode(ResultEnvelope<R>.self, from: line).result
        } catch {
            throw HerdrError.badResponse("\(request.method): \(error)")
        }
    }

    /// Sends `request` and returns the raw reply line. Throws `.api` for an error reply.
    @discardableResult
    public func send(_ request: HerdrRequest, timeout: Duration? = nil) async throws -> Data {
        onRequest?(request)
        let (path, timeout) = (socketPath, timeout ?? self.timeout)
        return try await Self.offPool {
            let connection = try HerdrConnection(path: path, timeout: timeout)
            defer { connection.close() }
            let id = Self.nextID()
            try connection.write(request.line(id: id))
            return try Self.reply(to: id, on: connection)
        }
    }

    /// Reads until the reply to `id`. Herdr answers a request it can't parse with `id: ""`, and a
    /// rejected subscription with a derived ID; on our own connection any error is ours.
    private static func reply(to id: String, on connection: HerdrConnection) throws -> Data {
        struct Header: Decodable {
            var id: String?
            var error: APIError?
            struct APIError: Decodable { var code: String; var message: String }
        }
        while let line = try connection.readLine() {
            guard let header = try? JSONDecoder().decode(Header.self, from: line) else { continue }
            if let error = header.error { throw HerdrError.api(code: error.code, message: error.message) }
            if header.id == id { return line }
        }
        throw HerdrError.unavailable("connection closed before the reply")
    }

    // MARK: Events

    /// Opens a dedicated connection subscribed to status changes of `agentPanes` plus the global
    /// pane events. Returns once Herdr acknowledged the subscription. Herdr rejects panes that no
    /// longer exist (`pane_not_found`), so reconcile right before subscribing.
    public func subscribe(agentPanes: some Sequence<String>) async throws -> HerdrEventStream {
        let request = HerdrRequest.subscribe(agentPanes: agentPanes)
        onRequest?(request)
        let (path, timeout) = (socketPath, timeout)
        let connection = try await Self.offPool {
            let connection = try HerdrConnection(path: path, timeout: timeout)
            do {
                let id = Self.nextID()
                try connection.write(request.line(id: id))
                _ = try Self.reply(to: id, on: connection)
                connection.setTimeout(nil)
                return connection
            } catch {
                connection.close()
                throw error
            }
        }
        return HerdrEventStream(connection)
    }

    /// Runs blocking socket work on a GCD thread instead of the cooperative pool.
    private static func offPool<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result { try work() })
            }
        }
    }
}

private struct ResultEnvelope<R: Decodable>: Decodable { var result: R }

/// Decoded events from one subscription connection. Ends when Herdr closes the connection or
/// `close()` is called.
public final class HerdrEventStream: Sendable {
    public let events: AsyncStream<HerdrEvent>
    private let connection: HerdrConnection

    init(_ connection: HerdrConnection) {
        self.connection = connection
        let (events, continuation) = AsyncStream.makeStream(of: HerdrEvent.self)
        self.events = events
        continuation.onTermination = { _ in connection.close() }
        // A long-lived blocking reader gets its own thread rather than holding a GCD worker.
        let thread = Thread {
            while let line = try? connection.readLine() {
                if let event = HerdrEvent.decode(line) { continuation.yield(event) }
            }
            continuation.finish()
        }
        thread.name = "nocchi.herdr.events"
        thread.start()
    }

    public func close() { connection.close() }
}
