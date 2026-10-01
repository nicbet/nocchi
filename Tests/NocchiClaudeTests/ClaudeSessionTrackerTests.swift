import Foundation
import NocchiCore
import Testing
@testable import NocchiClaude

@Suite struct ClaudeHookParsingTests {
    func parse(_ json: String) -> ClaudeHookEvent? { ClaudeHookEvent.parse(Data(json.utf8)) }

    @Test func mapsHookEventsToKinds() {
        #expect(parse(#"{"session_id":"s","hook_event_name":"SessionStart","source":"startup","cwd":"/r/app","transcript_path":"/t.jsonl"}"#)
            == ClaudeHookEvent(kind: .sessionStart, sessionID: "s", cwd: "/r/app", transcriptPath: "/t.jsonl"))
        #expect(parse(#"{"session_id":"s","hook_event_name":"UserPromptSubmit","prompt":"hi"}"#)?.kind == .promptSubmitted)
        #expect(parse(#"{"session_id":"s","hook_event_name":"PostToolUse","tool_name":"Edit"}"#)?.kind == .toolUsed)
        #expect(parse(#"{"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"Bash"}"#)?.kind == .needsInput)
        #expect(parse(#"{"session_id":"s","hook_event_name":"Notification","notification_type":"permission_prompt"}"#)?.kind == .needsInput)
        #expect(parse(#"{"session_id":"s","hook_event_name":"Notification","notification_type":"idle_prompt"}"#)?.kind == .idleReminder)
        #expect(parse(#"{"session_id":"s","hook_event_name":"Stop","stop_hook_active":false}"#)?.kind == .stopped)
        #expect(parse(#"{"session_id":"s","hook_event_name":"StopFailure","error":"rate_limit"}"#)?.kind == .failed("rate_limit"))
        #expect(parse(#"{"session_id":"s","hook_event_name":"SessionEnd","reason":"logout"}"#)?.kind == .sessionEnd)
        #expect(parse(#"{"session_id":"s","hook_event_name":"PreCompact"}"#)?.kind == .other)
        #expect(parse(#"{"hook_event_name":"Stop"}"#) == nil)
        #expect(parse("nope") == nil)
    }
}

@Suite struct ClaudeSessionTrackerTests {
    let t0 = Date(timeIntervalSince1970: 1_000)
    let t1 = Date(timeIntervalSince1970: 1_010)
    func event(_ kind: ClaudeHookEvent.Kind, _ id: String = "s1", pid: Int32? = 42, host: Int32? = 7, herdr: String? = nil) -> ClaudeHookEvent {
        ClaudeHookEvent(kind: kind, sessionID: id, cwd: "/work/app", processID: pid, hostID: host, herdrPane: herdr)
    }
    func status(_ tracker: ClaudeSessionTracker, _ id: String = "s1") -> AgentStatus? { tracker.agents[id]?.status }

    @Test func aTurnFromStartToFinish() {
        var tracker = ClaudeSessionTracker()
        let start = tracker.apply(event(.sessionStart), now: t0)
        guard case .upserted(let info) = start.first else { Issue.record("no agent"); return }
        #expect(info.ref == AgentRef(adapter: "claude", localID: "s1"))
        #expect(info.kind == .claude)
        #expect(info.sessionID == "s1")
        #expect(info.displayName == "app")
        #expect(info.status == .idle)

        _ = tracker.apply(event(.promptSubmitted), now: t0)
        #expect(status(tracker) == .working)
        _ = tracker.apply(event(.needsInput), now: t0)
        #expect(status(tracker) == .blocked)
        _ = tracker.apply(event(.toolUsed), now: t0)
        #expect(status(tracker) == .working, "approved: back to work")
        let stop = tracker.apply(event(.stopped), now: t1)
        #expect(status(tracker) == .done)
        #expect(stop.contains(.turnFinished(AgentRef(adapter: "claude", localID: "s1"))))
        #expect(tracker.apply(event(.idleReminder), now: t1).isEmpty, "still unread")
    }

    @Test func doneIsSeenWhenItsTerminalComesToTheFront() {
        var tracker = ClaudeSessionTracker()
        _ = tracker.apply(event(.promptSubmitted), now: t0)
        _ = tracker.apply(event(.stopped), now: t0)
        #expect(tracker.hostBecameFrontmost(99, now: t1).isEmpty, "another app")
        #expect(tracker.hostBecameFrontmost(7, now: t1).count == 1)
        #expect(status(tracker) == .idle)
    }

    @Test func failuresCarryTheirReason() {
        var tracker = ClaudeSessionTracker()
        _ = tracker.apply(event(.promptSubmitted), now: t0)
        _ = tracker.apply(event(.failed("rate_limit")), now: t0)
        #expect(status(tracker) == .error("rate_limit"))
    }

    @Test func sessionsEndOrDie() {
        var tracker = ClaudeSessionTracker()
        _ = tracker.apply(event(.sessionStart, "a", pid: 1), now: t0)
        _ = tracker.apply(event(.sessionStart, "b", pid: 2), now: t0)
        #expect(tracker.apply(event(.sessionEnd, "a"), now: t1) == [.removed(AgentRef(adapter: "claude", localID: "a"))])
        #expect(tracker.keepAlive { $0 != 2 } == [.removed(AgentRef(adapter: "claude", localID: "b"))])
        #expect(tracker.agents.isEmpty)
    }

    @Test func aSessionSeenMidTurnStillShowsUp() {
        var tracker = ClaudeSessionTracker()
        #expect(tracker.apply(event(.toolUsed), now: t0).count == 1)
        #expect(status(tracker) == .working)
    }

    @Test func herdrSessionsAreLeftToHerdr() {
        var tracker = ClaudeSessionTracker()
        #expect(tracker.apply(event(.sessionStart, herdr: "w1:p1"), now: t0).isEmpty)
        var standalone = ClaudeSessionTracker(leavesHerdrToHerdr: false)
        #expect(standalone.apply(event(.sessionStart, herdr: "w1:p1"), now: t0).count == 1)
    }
}

@Suite struct ClaudeRegistryTests {
    let t0 = Date(timeIntervalSince1970: 1_000)

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

    @Test func registryChangesDriveTheLifecycle() {
        var tracker = ClaudeSessionTracker()
        _ = tracker.applyRegistry([entry("idle")], context: here, now: t0)
        #expect(tracker.agents["s"]?.status == .idle)
        _ = tracker.applyRegistry([entry("busy")], context: here, now: t0)
        #expect(tracker.agents["s"]?.status == .working)
        let done = tracker.applyRegistry([entry("idle")], context: here, now: t0)
        #expect(tracker.agents["s"]?.status == .done)
        #expect(done.contains(.turnFinished(AgentRef(adapter: "claude", localID: "s"))))
        #expect(tracker.applyRegistry([entry("idle")], context: here, now: t0).isEmpty, "no change, no news")
        #expect(tracker.hosts["s"] == 7)
    }

    @Test func aPollNeverOverwritesFresherHookNews() {
        var tracker = ClaudeSessionTracker()
        _ = tracker.applyRegistry([entry("busy")], context: here, now: t0)
        _ = tracker.apply(ClaudeHookEvent(kind: .needsInput, sessionID: "s"), now: t0)
        _ = tracker.applyRegistry([entry("busy")], context: here, now: t0)
        #expect(tracker.agents["s"]?.status == .blocked, "registry still says busy: unchanged, so ignored")
    }

    @Test func goneFromTheRegistryIsGone() {
        var tracker = ClaudeSessionTracker()
        _ = tracker.applyRegistry([entry("idle")], context: here, now: t0)
        #expect(tracker.applyRegistry([], context: here, now: t0) == [.removed(AgentRef(adapter: "claude", localID: "s"))])
    }

    @Test func herdrPanesAreHerdrs() {
        var tracker = ClaudeSessionTracker()
        _ = tracker.applyRegistry([entry("idle", pid: 6, id: "h")], context: here, now: t0)
        #expect(tracker.agents.isEmpty)
    }
}
