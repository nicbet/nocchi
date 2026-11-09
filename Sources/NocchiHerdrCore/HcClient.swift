import Foundation
import NocchiHerdr
import Synchronization

/// Talks to one herdr-core. Every request gets its own connection (simple, and a request that
/// was written is never resent); an event subscription keeps a dedicated one.
/// Errors come back as `HerdrError`: `.api(code:)` carries the error's stable `data.kind`.
public struct HcClient: Sendable {
    public let socketPath: String
    public var timeout: Duration
    /// Sees every request before it's sent. Integration tests record them for the schema check.
    public var onRequest: (@Sendable (HcRequest) -> Void)?

    public init(socketPath: String = HerdrCore.socketPath(), timeout: Duration = .seconds(5), onRequest: (@Sendable (HcRequest) -> Void)? = nil) {
        self.socketPath = socketPath
        self.timeout = timeout
        self.onRequest = onRequest
    }

    private static let counter = Mutex(0)
    private static func nextID() -> String { "nocchi-\(counter.withLock { $0 += 1; return $0 })" }

    public struct Hello: Decodable, Sendable {
        public var version: String
        public var generation: Int
    }

    /// The handshake. Throws `.unavailable` for a core that speaks another generation.
    public func hello() async throws -> Hello {
        let hello = try await call(.hello, as: Hello.self, timeout: .seconds(2))
        guard hello.generation == HerdrCore.supportedGeneration else {
            throw HerdrError.unavailable("herdr-core \(hello.version) speaks API generation \(hello.generation); nocchi supports \(HerdrCore.supportedGeneration)")
        }
        return hello
    }

    /// herdr-app's layout, or nil if it never wrote one.
    public func appLayout() async throws -> HerdrAppLayout? {
        struct Doc: Decodable, Sendable { var value: HerdrAppLayout? }
        return try await call(.appLayout, as: Doc.self).value
    }

    /// Sends `request` and decodes its `result` as `R`.
    public func call<R: Decodable & Sendable>(_ request: HcRequest, as: R.Type, timeout: Duration? = nil) async throws -> R {
        let line = try await send(request, timeout: timeout)
        do {
            return try JSONDecoder().decode(ResultEnvelope<R>.self, from: line).result
        } catch {
            throw HerdrError.badResponse("\(request.method): \(error)")
        }
    }

    /// Sends `request` and returns the raw reply line. Throws `.api` for an error reply.
    @discardableResult
    public func send(_ request: HcRequest, timeout: Duration? = nil) async throws -> Data {
        onRequest?(request)
        let (path, timeout) = (socketPath, timeout ?? self.timeout)
        return try await Self.offPool {
            let connection = try Self.connect(path, timeout: timeout)
            defer { connection.close() }
            let id = Self.nextID()
            try connection.write(request.line(id: id))
            return try Self.reply(to: id, on: connection)
        }
    }

    /// Subscribes to every terminal. Returns the snapshot and the stream of what follows.
    public func subscribe() async throws -> (HcSubscription, HcEventStream) {
        let request = HcRequest.subscribe
        onRequest?(request)
        let (path, timeout) = (socketPath, timeout)
        return try await Self.offPool {
            let connection = try Self.connect(path, timeout: timeout)
            do {
                let id = Self.nextID()
                try connection.write(request.line(id: id))
                let line = try Self.reply(to: id, on: connection)
                let subscription: HcSubscription
                do {
                    subscription = try JSONDecoder().decode(ResultEnvelope<HcSubscription>.self, from: line).result
                } catch {
                    throw HerdrError.badResponse("events.subscribe: \(error)")
                }
                connection.setTimeout(nil)
                return (subscription, HcEventStream(connection))
            } catch {
                connection.close()
                throw error
            }
        }
    }

    private static func connect(_ path: String, timeout: Duration) throws -> HerdrConnection {
        do {
            return try HerdrConnection(path: path, timeout: timeout)
        } catch HerdrError.unavailable(let reason) where reason == "Herdr isn't running" {
            throw HerdrError.unavailable("herdr-core isn't running")
        }
    }

    /// Reads until the reply to `id`, skipping notifications.
    private static func reply(to id: String, on connection: HerdrConnection) throws -> Data {
        struct Header: Decodable {
            var id: String?
            var error: APIError?
            struct APIError: Decodable {
                var message: String
                var data: Details?
                struct Details: Decodable { var kind: String? }
            }
        }
        while let line = try connection.readLine() {
            guard let header = try? JSONDecoder().decode(Header.self, from: line), header.id == id else { continue }
            if let error = header.error {
                throw HerdrError.api(code: error.data?.kind ?? error.message, message: error.message)
            }
            return line
        }
        throw HerdrError.unavailable("connection closed before the reply")
    }

    /// Runs blocking socket work on a GCD thread instead of the cooperative pool.
    static func offPool<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result { try work() })
            }
        }
    }
}

private struct ResultEnvelope<R: Decodable>: Decodable { var result: R }

/// Decoded notifications from one subscription connection. Ends when herdr-core closes the
/// connection or `close()` is called.
public final class HcEventStream: Sendable {
    public let events: AsyncStream<HcEvent>
    private let connection: HerdrConnection

    init(_ connection: HerdrConnection) {
        self.connection = connection
        let (events, continuation) = AsyncStream.makeStream(of: HcEvent.self)
        self.events = events
        continuation.onTermination = { _ in connection.close() }
        // A long-lived blocking reader gets its own thread rather than holding a GCD worker.
        let thread = Thread {
            while let line = try? connection.readLine() {
                if let event = HcEvent.decode(line) { continuation.yield(event) }
            }
            continuation.finish()
        }
        thread.name = "nocchi.herdr-core.events"
        thread.start()
    }

    public func close() { connection.close() }
}

/// Talks to herdr-app's control socket: one JSON line out, one back, per connection.
public struct HerdrAppClient: Sendable {
    public let socketPath: String
    public var timeout: Duration

    public init(socketPath: String = HerdrCore.appSocketPath(), timeout: Duration = .seconds(5)) {
        self.socketPath = socketPath
        self.timeout = timeout
    }

    /// The open window's spaces, tabs and terminals.
    public struct Tree: Decodable, Sendable {
        public var spaces: [Space]
        public struct Space: Decodable, Sendable {
            public var id: String
            public var folder: String?
            public var machine: String?
            public var tabs: [Tab]
        }
        public struct Tab: Decodable, Sendable {
            public var id: String
            public var terminals: [Terminal]
        }
        public struct Terminal: Decodable, Sendable {
            public var terminal: String
        }

        /// Every terminal shown.
        public var terminals: Set<String> { Set(spaces.flatMap { $0.tabs.flatMap { $0.terminals.map(\.terminal) } }) }
    }

    public func ls() async throws -> Tree {
        let line = try await request(["ls": [:]])
        do {
            return try JSONDecoder().decode(Tree.self, from: line)
        } catch {
            throw HerdrError.badResponse("ls: \(error)")
        }
    }

    /// Runs a window command (`herdr-app commands` lists them).
    @discardableResult
    public func run(_ command: String, _ args: [String: JSONValue] = [:]) async throws -> Data {
        try await request(["do": .string(command), "args": .object(args)])
    }

    /// Sends one message and returns the reply. Throws `.api(code: "app")` for `{"error": …}`.
    func request(_ message: [String: JSONValue]) async throws -> Data {
        let (path, timeout) = (socketPath, timeout)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var data = try encoder.encode(message)
        data.append(0x0A)
        let payload = data
        let reply = try await HcClient.offPool { () throws -> Data in
            let connection: HerdrConnection
            do {
                connection = try HerdrConnection(path: path, timeout: timeout)
            } catch HerdrError.unavailable(let reason) where reason == "Herdr isn't running" {
                throw HerdrError.unavailable("Herdr's window isn't open")
            }
            defer { connection.close() }
            try connection.write(payload)
            guard let line = try connection.readLine() else { throw HerdrError.unavailable("herdr-app closed the connection") }
            return line
        }
        struct Failure: Decodable { var error: String }
        if let failure = try? JSONDecoder().decode(Failure.self, from: reply) {
            throw HerdrError.api(code: "app", message: failure.error)
        }
        return reply
    }
}
