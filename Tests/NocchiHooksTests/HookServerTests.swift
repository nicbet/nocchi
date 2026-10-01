import Foundation
import NocchiHookProtocol
import Testing
@testable import NocchiHooks

@Suite struct HookServerTests {
    /// The `nocchi-hook` binary SwiftPM built next to the tests.
    var hookBinary: URL {
        Bundle(for: Marker.self).bundleURL.deletingLastPathComponent().appending(path: "nocchi-hook")
    }

    func run(_ arguments: [String], input: String, socket: String, environment: [String: String] = [:]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = hookBinary
        process.arguments = arguments
        // Start clean: these tests may run inside Herdr or iTerm, whose variables would leak in.
        var env = ProcessInfo.processInfo.environment.filter { !HookMessage.environmentKeys.contains($0.key) }
        env["NOCCHI_HOOK_SOCKET"] = socket
        env.merge(environment) { $1 }
        process.environment = env
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (process.terminationStatus, output)
    }

    func socketPath() -> String { "/tmp/nocchi-hook-test-\(UUID().uuidString.prefix(8)).sock" }

    @Test func forwardsHookInputWithEnvironment() async throws {
        let path = socketPath()
        let server = HookServer(path: path)
        try server.start()
        defer { server.stop() }
        let messages = server.messages(for: "claude")

        let input = #"{"session_id":"abc","hook_event_name":"Stop","cwd":"/x"}"#
        let result = try run(["claude"], input: input, socket: path, environment: ["HERDR_PANE_ID": "w1:p2", "SECRET": "no"])
        #expect(result.status == 0)
        #expect(result.output.isEmpty, "hooks must print nothing")

        var iterator = messages.makeAsyncIterator()
        let message = try #require(await iterator.next())
        #expect(message.agent == "claude")
        #expect(message.environment == ["HERDR_PANE_ID": "w1:p2"], "only the keys nocchi needs")
        #expect(message.parentPID > 1)
        let decoded = try JSONSerialization.jsonObject(with: message.input) as? [String: String]
        #expect(decoded?["session_id"] == "abc")
    }

    @Test func messagesGoOnlyToTheirAgent() async throws {
        let path = socketPath()
        let server = HookServer(path: path)
        try server.start()
        defer { server.stop() }
        let codex = server.messages(for: "codex")
        _ = try run(["claude"], input: "{}", socket: path)
        _ = try run(["codex"], input: #"{"session_id":"c"}"#, socket: path)
        var iterator = codex.makeAsyncIterator()
        let message = try #require(await iterator.next())
        #expect(message.agent == "codex")
    }

    @Test func bigToolPayloadsAreDropped() async throws {
        let path = socketPath()
        let server = HookServer(path: path)
        try server.start()
        defer { server.stop() }
        let messages = server.messages(for: "claude")
        let big = String(repeating: "x", count: 200_000)
        _ = try run(["claude"], input: #"{"session_id":"s","hook_event_name":"PreToolUse","tool_input":{"content":"\#(big)"}}"#, socket: path)
        var iterator = messages.makeAsyncIterator()
        let message = try #require(await iterator.next())
        #expect(message.input.count < 1000)
        let decoded = try JSONSerialization.jsonObject(with: message.input) as? [String: Any]
        #expect(decoded?["session_id"] as? String == "s")
        #expect(decoded?["tool_input"] == nil)
    }

    @Test func withoutTheAppTheHookStillSucceedsQuietly() throws {
        let result = try run(["claude"], input: "{}", socket: "/tmp/nocchi-nobody-listens.sock")
        #expect(result.status == 0)
        #expect(result.output.isEmpty)
    }
}

private final class Marker {}
