import Foundation
import NocchiHerdr
import Synchronization
@testable import NocchiHerdrCore

/// A throwaway herdr-core for integration tests: its own socket, state and config under
/// `/tmp/nocchi-it-<random>` (macOS limits socket paths to 104 bytes), every inherited `HC_*`
/// variable stripped, so running the suite inside an hc terminal never touches the operator's
/// core. herdr-app is never involved: tests point the adapter at a socket nobody listens on.
///
/// Agents are simulated by a shell loop that prints each line it's sent as an OSC 7501 report
/// (`state=working:app=fake`), the way real agents report their status.
final class IsolatedHerdrCore: Sendable {
    let name: String
    let socketPath: String
    let directory: URL
    private let executable: URL
    /// Every request the adapter under test sent, for the schema drift check.
    let recorded = Mutex<[HcRequest]>([])

    /// `nil` when hc isn't installed.
    static func start() throws -> IsolatedHerdrCore? {
        guard let executable = findHc() else { return nil }
        let core = try IsolatedHerdrCore(executable: executable)
        try core.launch()
        return core
    }

    static func findHc() -> URL? {
        let path = ProcessInfo.processInfo.environment["PATH", default: ""].split(separator: ":").map(String.init)
        let candidates = path + [NSHomeDirectory() + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        return candidates.lazy.map { URL(fileURLWithPath: $0).appending(path: "hc") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private init(executable: URL) throws {
        self.executable = executable
        name = "nocchi-it-" + String(UInt32.random(in: .min ... .max), radix: 16)
        directory = URL(fileURLWithPath: "/tmp").appending(path: name)
        socketPath = directory.appending(path: "hc.sock").path
        // Never touch the operator's own core.
        guard socketPath != HerdrCore.socketPath() else { throw HerdrError.unavailable("refusing to run against \(socketPath)") }
        for sub in ["state", "config"] {
            try FileManager.default.createDirectory(at: directory.appending(path: sub), withIntermediateDirectories: true)
        }
    }

    var client: HcClient {
        HcClient(socketPath: socketPath) { [self] request in recorded.withLock { $0.append(request) } }
    }

    /// A client whose requests aren't recorded: the test driving the core, not the adapter.
    var driver: HcClient { HcClient(socketPath: socketPath, timeout: .seconds(20)) }

    /// A herdr-app nobody runs.
    var noWindow: HerdrAppClient { HerdrAppClient(socketPath: directory.appending(path: "no-app.sock").path) }

    private var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("HC_") && !$0.key.hasPrefix("HERDR") }
        env["HC_SOCKET"] = socketPath
        env["XDG_STATE_HOME"] = directory.appending(path: "state").path
        env["XDG_CONFIG_HOME"] = directory.appending(path: "config").path
        return env
    }

    /// Starts the core (it runs in the background) and waits until it answers `hello`.
    func launch() throws {
        run(["server", "start"])
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if (try? blockingHello()) == true { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw HerdrError.unavailable("isolated herdr-core \(name) didn't answer hello")
    }

    private func blockingHello() throws -> Bool {
        let connection = try HerdrConnection(path: socketPath, timeout: .seconds(1))
        defer { connection.close() }
        try connection.write(HcRequest.hello.line(id: "it"))
        return try connection.readLine().map { String(decoding: $0, as: UTF8.self).contains("generation") } ?? false
    }

    /// Restarts the core; programs keep running and the new core adopts them.
    func restart() throws {
        run(["server", "restart"])
        try launch()
    }

    func stop() {
        run(["server", "stop"])
        try? FileManager.default.removeItem(at: directory)
    }

    @discardableResult
    func run(_ arguments: [String]) -> String {
        let command = Process()
        command.executableURL = executable
        command.arguments = arguments
        command.environment = environment
        let pipe = Pipe()
        command.standardOutput = pipe
        command.standardError = FileHandle.nullDevice
        try? command.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        command.waitUntilExit()
        return output
    }

    // MARK: Driving agents

    /// Starts a fake agent reporting `state`; returns its terminal.
    func addAgent(state: String = "idle", app: String = "fake") async throws -> String {
        struct Run: Decodable, Sendable { var address: String }
        let loop = #"printf '\033]7501;%s\007' "$0"; while IFS= read -r l; do printf '\033]7501;%s\007' "$l"; done"#
        let request = HcRequest(method: "terminal.run", params: [
            "argv": ["/bin/sh", "-c", .string(loop), .string("state=\(state):app=\(app)")],
            "cwd": .string(directory.path), "no_parent": true,
        ])
        return try await driver.call(request, as: Run.self).address
    }

    /// Makes the fake agent report `state`.
    func report(_ terminal: String, _ state: String, app: String = "fake") async throws {
        try await driver.send(HcRequest(method: "terminal.send", params: [
            "terminal": .string(terminal), "text": .string("state=\(state):app=\(app)"), "force": true,
        ]), timeout: .seconds(20))
    }

    func kill(_ terminal: String) async throws {
        try await driver.send(HcRequest(method: "terminal.kill", params: ["terminal": .string(terminal)]), timeout: .seconds(20))
    }
}

/// Checks requests against the installed hc's OpenRPC document (`hc schema`), so an hc upgrade
/// that renames a method or parameter fails a test instead of failing silently in the app.
struct HcSchema {
    private let methods: [String: [[String: Any]]]

    /// `nil` when hc isn't installed.
    static func installed() throws -> HcSchema? {
        guard let hc = IsolatedHerdrCore.findHc() else { return nil }
        let process = Process()
        process.executableURL = hc
        process.arguments = ["schema"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let methods = root["methods"] as? [[String: Any]] else { return nil }
        var byName: [String: [[String: Any]]] = [:]
        for method in methods {
            guard let name = method["name"] as? String else { continue }
            byName[name] = method["params"] as? [[String: Any]] ?? []
        }
        return HcSchema(methods: byName)
    }

    /// Problems with `request`, empty if it matches: the method exists, every parameter is
    /// known, required ones are present, and string parameters are strings.
    func validate(_ request: HcRequest) -> [String] {
        guard let params = methods[request.method] else { return ["\(request.method): no such method"] }
        var problems: [String] = []
        let known = Dictionary(uniqueKeysWithValues: params.compactMap { p in (p["name"] as? String).map { ($0, p) } })
        for (name, value) in request.params {
            guard let param = known[name] else { problems.append("\(request.method): unknown parameter \(name)"); continue }
            let type = (param["schema"] as? [String: Any])?["type"]
            let types = (type as? [String]) ?? (type as? String).map { [$0] } ?? []
            if case .string = value, !types.isEmpty, !types.contains("string") {
                problems.append("\(request.method).\(name): expected \(types), got a string")
            }
        }
        for (name, param) in known where param["required"] as? Bool == true && request.params[name] == nil {
            problems.append("\(request.method): missing \(name)")
        }
        return problems
    }
}
