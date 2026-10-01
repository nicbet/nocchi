import Foundation
import NocchiCore
import Testing
@testable import NocchiCodex

@Suite struct CodexSessionTrackerTests {
    let t0 = Date(timeIntervalSince1970: 1_000)
    let ref = AgentRef(adapter: "codex", localID: "s1")
    func session(_ id: String = "s1", host: Int32? = 7) -> CodexSession {
        CodexSession(pid: 42, sessionID: id, rollout: URL(fileURLWithPath: "/r/\(id).jsonl"), cwd: "/work/api", title: "Fix the flaky test", hostID: host)
    }

    @Test func discoveryAddsAndRemoves() {
        var tracker = CodexSessionTracker()
        let added = tracker.update(live: [session()], now: t0)
        guard case .upserted(let info) = added.first else { Issue.record("no agent"); return }
        #expect(info.kind == .codex)
        #expect(info.displayName == "api")
        #expect(info.title == "Fix the flaky test")
        #expect(tracker.update(live: [session()], now: t0).isEmpty, "no change")
        #expect(tracker.update(live: [], now: t0) == [.removed(ref)])
    }

    @Test func aTurnFromTheRollout() {
        var tracker = CodexSessionTracker()
        _ = tracker.update(live: [session()], now: t0)
        let working = tracker.apply([.turnStarted, .step("Reading main.go"), .step("Editing main.go")], to: "s1", now: t0)
        #expect(tracker.agents["s1"]?.status == .working)
        #expect(working.contains(.step(ref, "Editing main.go")))
        let done = tracker.apply([.message("Done."), .turnCompleted(lastMessage: "All tests pass.")], to: "s1", now: t0)
        #expect(tracker.agents["s1"]?.status == .done)
        #expect(done.contains(.turnFinished(ref)))
        #expect(done.last == .message(ref, "All tests pass."), "the final answer wins")
        #expect(tracker.hostBecameFrontmost(7, now: t0).count == 1)
        #expect(tracker.agents["s1"]?.status == .idle)
    }

    @Test func replayShowsTheLatestStateQuietly() {
        var tracker = CodexSessionTracker()
        _ = tracker.update(live: [session()], now: t0)
        let events = tracker.apply([.turnStarted, .step("a"), .step("b"), .step("c"), .turnCompleted(lastMessage: "Old news.")],
                                   to: "s1", replay: true, now: t0)
        #expect(tracker.agents["s1"]?.status == .idle, "finished before nocchi looked: not unread")
        #expect(!events.contains(.turnFinished(ref)))
        #expect(events.filter { if case .step = $0 { true } else { false } }.count == 2)
        var midTurn = CodexSessionTracker()
        _ = midTurn.update(live: [session()], now: t0)
        _ = midTurn.apply([.turnCompleted(lastMessage: nil), .turnStarted], to: "s1", replay: true, now: t0)
        #expect(midTurn.agents["s1"]?.status == .working)
    }

    @Test func interruptionsAndHooks() {
        var tracker = CodexSessionTracker()
        _ = tracker.update(live: [session()], now: t0)
        _ = tracker.apply([.turnStarted], to: "s1", now: t0)
        #expect(tracker.applyHook("PermissionRequest", session: "s1", now: t0).count == 1)
        #expect(tracker.agents["s1"]?.status == .blocked)
        _ = tracker.applyHook("PostToolUse", session: "s1", now: t0)
        #expect(tracker.agents["s1"]?.status == .working)
        let aborted = tracker.apply([.turnAborted], to: "s1", now: t0)
        #expect(tracker.agents["s1"]?.status == .idle)
        #expect(!aborted.contains(.turnFinished(ref)), "you stopped it: nothing to celebrate")
        #expect(tracker.applyHook("PermissionRequest", session: "nobody", now: t0).isEmpty)
    }
}
