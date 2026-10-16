import Foundation
import NocchiCore
import Testing
@testable import NocchiClaude

@Suite struct ClaudeRegistryTests {
    let t0 = Date(timeIntervalSince1970: 1_000)
    let ref = AgentRef(adapter: "claude", localID: "s")

    @Test func parsesInteractiveSessionsOnly() {
        let interactive = #"{"pid":10915,"sessionId":"36ee","cwd":"/r/nocchi","kind":"interactive","name":"nocchi-b8","status":"busy","statusUpdatedAt":1790850243401}"#
        let entry = ClaudeRegistryEntry.parse(Data(interactive.utf8))
        #expect(entry?.pid == 10915)
        #expect(entry?.sessionID == "36ee")
        #expect(entry?.status == "busy")
        #expect(entry?.statusUpdatedAt == Date(timeIntervalSince1970: 1790850243.401))
        #expect(ClaudeRegistryEntry.parse(Data(#"{"pid":1,"sessionId":"x","kind":"headless"}"#.utf8)) == nil)
        #expect(ClaudeRegistryEntry.parse(Data("{}".utf8)) == nil)
    }

    @Test func readsTheDirectoryAndSkipsDeadProcesses() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "nocchi-registry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try #"{"pid":1,"sessionId":"a","kind":"interactive"}"#.write(to: dir.appending(path: "1.json"), atomically: true, encoding: .utf8)
        try #"{"pid":2,"sessionId":"b","kind":"interactive"}"#.write(to: dir.appending(path: "2.json"), atomically: true, encoding: .utf8)
        try "x".write(to: dir.appending(path: "2.key"), atomically: true, encoding: .utf8)
        #expect(ClaudeRegistryEntry.read(dir, isAlive: { $0 == 2 }).map(\.sessionID) == ["b"])
    }

    func entry(_ status: String, pid: Int32 = 5, id: String = "s") -> ClaudeRegistryEntry {
        ClaudeRegistryEntry(pid: pid, sessionID: id, cwd: "/r/app", status: status)
    }
    let here: [Int32: (insideHerdr: Bool, host: Int32?, tty: String?)] = [5: (false, 7, "ttys001"), 6: (true, 7, "ttys002")]

    func run(_ statuses: [String]) -> (ClaudeSessionTracker, [AgentEvent]) {
        var tracker = ClaudeSessionTracker()
        var events: [AgentEvent] = []
        for status in statuses { events += tracker.applyRegistry([entry(status)], context: here, now: t0) }
        return (tracker, events)
    }

    @Test func aTurnFromStartToFinish() {
        let (tracker, events) = run(["idle", "busy", "shell", "busy", "idle"])
        #expect(tracker.agents["s"]?.status == .done)
        #expect(tracker.agents["s"]?.kind == .claude)
        #expect(tracker.agents["s"]?.displayName == "app")
        #expect(events.filter { $0 == .turnFinished(ref) }.count == 1, "celebrated once")
    }

    /// Recorded with Claude Code 2.1.286: a permission prompt, declined; then a question, answered.
    @Test func waitingForYou() {
        let (declined, _) = run(["idle", "busy", "waiting"])
        #expect(declined.agents["s"]?.status == .blocked)
        let (afterDecline, events) = run(["idle", "busy", "waiting", "idle"])
        #expect(afterDecline.agents["s"]?.status == .idle, "answered, not finished")
        #expect(!events.contains(.turnFinished(ref)))
        let (answered, _) = run(["idle", "busy", "waiting", "busy", "idle"])
        #expect(answered.agents["s"]?.status == .done)
    }

    @Test func doneIsSeenWhenItsTerminalComesToTheFront() {
        var (tracker, _) = run(["idle", "busy", "idle"])
        #expect(tracker.hostBecameFrontmost(99, now: t0).isEmpty, "another app")
        #expect(tracker.hostBecameFrontmost(7, now: t0).count == 1)
        #expect(tracker.agents["s"]?.status == .idle)
    }

    @Test func noChangeNoNews() {
        var (tracker, _) = run(["idle", "busy"])
        #expect(tracker.applyRegistry([entry("busy")], context: here, now: t0).isEmpty)
        #expect(tracker.applyRegistry([entry("mystery")], context: here, now: t0).isEmpty, "unknown statuses change nothing")
    }

    @Test func goneFromTheRegistryIsGone() {
        var (tracker, _) = run(["idle"])
        #expect(tracker.applyRegistry([], context: here, now: t0) == [.removed(ref)])
    }

    @Test func herdrPanesAreHerdrs() {
        var tracker = ClaudeSessionTracker()
        _ = tracker.applyRegistry([entry("idle", pid: 6, id: "h")], context: here, now: t0)
        #expect(tracker.agents.isEmpty)
        var standalone = ClaudeSessionTracker(leavesHerdrToHerdr: false)
        _ = standalone.applyRegistry([entry("idle", pid: 6, id: "h")], context: here, now: t0)
        #expect(standalone.agents.count == 1)
    }

    @Test func hostIsTheTerminalAndItsWindowHints() {
        var tracker = ClaudeSessionTracker()
        _ = tracker.applyRegistry([entry("idle")], context: here, now: t0)
        #expect(tracker.agents["s"]?.host == AgentHost(pid: 7, windowHints: ["app"]), "the folder, before a title")

        let events = tracker.applyRegistry([entry("idle")], context: here, titles: ["s": "Fix the login bug"], now: t0)
        #expect(tracker.agents["s"]?.host == AgentHost(pid: 7, windowHints: ["Fix the login bug", "app"]))
        #expect(events.count == 1, "a new title is news")
        #expect(tracker.agents["s"]?.status == .idle)
    }

    @Test func noHostWhereTheTerminalIsUnknown() {
        var tracker = ClaudeSessionTracker()
        let elsewhere: [Int32: (insideHerdr: Bool, host: Int32?, tty: String?)] = [5: (false, nil, nil)]
        _ = tracker.applyRegistry([entry("idle")], context: elsewhere, titles: ["s": "Over SSH"], now: t0)
        #expect(tracker.agents["s"] != nil)
        #expect(tracker.agents["s"]?.host == nil)
    }
}
