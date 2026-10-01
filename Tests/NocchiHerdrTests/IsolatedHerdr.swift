import Foundation
import Synchronization
@testable import NocchiHerdr

/// A throwaway Herdr server for integration tests (the harness pattern from an earlier project):
/// `herdr --session nocchi-it-<random> server` with its own minimal config (non-login `/bin/sh`
/// panes, so dotfiles never leak in) and every inherited `HERDR_*` variable stripped, so running
/// the suite inside a Herdr pane never touches the operator's session.
///
/// Agents are simulated with `pane.report_agent`, the call agent hooks use, so no fake agent
/// binary is needed.
final class IsolatedHerdr: Sendable {
    let session: String
    let socketPath: String
    private let dir: URL
    private let executable: URL
    private let process = Mutex<Process?>(nil)
    /// Every request the adapter under test sent, for the schema drift check.
    let recorded = Mutex<[HerdrRequest]>([])

    /// `nil` when Herdr isn't installed.
    static func start() throws -> IsolatedHerdr? {
        guard let executable = findHerdr() else { return nil }
        let herdr = try IsolatedHerdr(executable: executable)
        try herdr.launch()
        return herdr
    }

    static func findHerdr() -> URL? {
        let path = ProcessInfo.processInfo.environment["PATH", default: ""].split(separator: ":").map(String.init)
        let candidates = path + [NSHomeDirectory() + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        return candidates.lazy.map { URL(fileURLWithPath: $0).appending(path: "herdr") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private init(executable: URL) throws {
        self.executable = executable
        session = "nocchi-it-" + String(UInt32.random(in: .min ... .max), radix: 16)
        socketPath = Herdr.socketPath(session: session)
        // Never touch the operator's own Herdr.
        guard session.hasPrefix("nocchi-it-"), socketPath != Herdr.socketPath() else {
            throw HerdrError.unavailable("refusing to run against \(socketPath)")
        }
        // Keep it under /tmp: macOS limits socket paths to 104 bytes.
        dir = URL(fileURLWithPath: "/tmp").appending(path: session)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "[terminal]\ndefault_shell = \"/bin/sh\"\nshell_mode = \"non_login\"\n"
            .write(to: dir.appending(path: "config.toml"), atomically: true, encoding: .utf8)
    }

    var client: HerdrClient {
        HerdrClient(socketPath: socketPath) { [self] request in recorded.withLock { $0.append(request) } }
    }

    /// A client whose requests aren't recorded: the test driving Herdr, not the adapter.
    var driver: HerdrClient { HerdrClient(socketPath: socketPath) }

    /// Starts the server and waits until it answers `ping`.
    func launch() throws {
        let server = Process()
        server.executableURL = executable
        server.arguments = ["--session", session, "server"]
        var env = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("HERDR_") }
        env["HERDR_CONFIG_PATH"] = dir.appending(path: "config.toml").path
        server.environment = env
        let log = dir.appending(path: "herdr.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        handle.seekToEndOfFile()
        server.standardOutput = handle
        server.standardError = handle
        try server.run()
        process.withLock { $0 = server }

        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if (try? HerdrConnection(path: socketPath, timeout: .seconds(1))) != nil,
               (try? blockingPing()) == true { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw HerdrError.unavailable("isolated Herdr \(session) didn't answer ping (log: \(log.path))")
    }

    private func blockingPing() throws -> Bool {
        let connection = try HerdrConnection(path: socketPath, timeout: .seconds(1))
        defer { connection.close() }
        try connection.write(HerdrRequest.ping.line(id: "it"))
        return try connection.readLine().map { String(decoding: $0, as: UTF8.self).contains("pong") } ?? false
    }

    /// Stops the server but keeps the session, like an operator restarting Herdr.
    func halt() {
        guard let server = process.withLock({ p in defer { p = nil }; return p }) else { return }
        run(["session", "stop", session])
        let deadline = Date().addingTimeInterval(10)
        while server.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if server.isRunning { server.terminate(); server.waitUntilExit() }
    }

    func stop() {
        halt()
        run(["session", "delete", session])
        try? FileManager.default.removeItem(at: dir)
    }

    private func run(_ arguments: [String]) {
        let command = Process()
        command.executableURL = executable
        command.arguments = arguments
        command.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("HERDR_") }
        command.standardOutput = FileHandle.nullDevice
        command.standardError = FileHandle.nullDevice
        try? command.run()
        command.waitUntilExit()
    }

    // MARK: Driving agents

    /// Opens a workspace and returns its root pane.
    func openPane(label: String, focus: Bool = false) async throws -> String {
        struct Created: Decodable, Sendable { var root_pane: Pane; struct Pane: Decodable, Sendable { var pane_id: String } }
        let request = HerdrRequest(method: "workspace.create", params: ["cwd": "/tmp", "label": .string(label), "focus": .bool(focus)])
        return try await driver.call(request, as: Created.self).root_pane.pane_id
    }

    /// Makes `pane` look like a running agent in `state` ("idle", "working", "blocked", "unknown").
    func report(_ pane: String, _ state: String, agent: String = "claude") async throws {
        try await driver.send(HerdrRequest(method: "pane.report_agent", params: [
            "pane_id": .string(pane), "source": "nocchi-it", "agent": .string(agent), "state": .string(state),
        ]))
    }

    func addAgent(label: String = "agent", state: String = "idle", focus: Bool = false) async throws -> String {
        let pane = try await openPane(label: label, focus: focus)
        try await report(pane, state)
        return pane
    }

    func close(_ pane: String) async throws {
        try await driver.send(.closePane(pane))
    }
}
