import Foundation
import NocchiCore
import Testing
@testable import NocchiHerdr

/// Fixture tests for Herdr's quirks.
@Suite struct HerdrTrackerTests {
    let t0 = Date(timeIntervalSince1970: 1_000)
    let t1 = Date(timeIntervalSince1970: 1_010)

    func ref(_ pane: String) -> AgentRef { AgentRef(adapter: "herdr", localID: pane) }

    func pane(_ id: String, agent: String? = "claude", status: String? = "idle", title: String? = nil, tab: String? = nil) -> HerdrPane {
        HerdrPane(paneID: id, workspaceID: "w1", tabID: tab, agent: agent, agentStatus: status, cwd: "/work/\(id)", title: title)
    }

    func agents(_ events: [AgentEvent]) -> [AgentInfo] {
        for case .snapshot(let infos) in events { return infos }
        return []
    }

    @Test func snapshotMapsPanesToAgents() {
        var tracker = HerdrTracker(adapter: "herdr")
        let snapshot = HerdrSnapshot(
            focusedPaneID: "w1:p2",
            agents: [
                HerdrPane(paneID: "w1:p1", workspaceID: "w1", tabID: "w1:t1", agent: "claude", agentStatus: "working",
                          cwd: "/work/nocchi", title: "Notch app", sessionID: "abc"),
                pane("w1:p2", agent: "codex", status: "blocked", tab: "w1:t2"),
            ],
            tabs: [.init(tabID: "w1:t1", label: "Nocchi"), .init(tabID: "w1:t2", label: "2")]
        )
        let infos = agents(tracker.apply(snapshot, now: t0))
        #expect(infos.map(\.ref.localID) == ["w1:p1", "w1:p2"])
        #expect(infos[0] == AgentInfo(
            ref: ref("w1:p1"), kind: .claude, status: .working, name: "Nocchi", title: "Notch app",
            cwd: URL(fileURLWithPath: "/work/nocchi", isDirectory: true), sessionID: "abc", isFocused: false, changedAt: t0
        ))
        #expect(infos[1].kind == .codex)
        #expect(infos[1].status == .blocked)
        #expect(infos[1].name == nil, "numbered tabs aren't names")
        #expect(infos[1].isFocused)
        #expect(tracker.agentPanes == ["w1:p1", "w1:p2"])
    }

    @Test func pendingLaunchIsStartingNotGone() {
        var tracker = HerdrTracker(adapter: "herdr")
        let launching = agents(tracker.apply(HerdrSnapshot(agents: [pane("w1:p1", agent: "", status: "unknown")]), now: t0))
        #expect(launching.map(\.status) == [.starting])
        #expect(tracker.agentPanes == ["w1:p1"], "subscribe to its status changes right away")

        let ready = agents(tracker.apply(HerdrSnapshot(agents: [pane("w1:p1", status: "unknown")]), now: t1))
        #expect(ready.map(\.status) == [.idle])
        #expect(ready.map(\.kind) == [.claude])
    }

    @Test func unknownKeepsThePreviousStatus() {
        var tracker = HerdrTracker(adapter: "herdr")
        _ = tracker.apply(HerdrSnapshot(agents: [pane("w1:p1", status: "working")]), now: t0)
        let out = tracker.apply(.statusChanged(pane: "w1:p1", agent: "claude", status: "unknown", title: nil), now: t1)
        #expect(out.events.isEmpty)
        #expect(tracker.agents["w1:p1"]?.status == .working)
        #expect(tracker.agents["w1:p1"]?.changedAt == t0)

        let snapshot = agents(tracker.apply(HerdrSnapshot(agents: [pane("w1:p1", status: "unknown")]), now: t1))
        #expect(snapshot.map(\.status) == [.working])
    }

    @Test func focusedTurnGoingStraightToIdleStillFinishes() {
        var tracker = HerdrTracker(adapter: "herdr")
        _ = tracker.apply(HerdrSnapshot(focusedPaneID: "w1:p1", agents: [pane("w1:p1", status: "working")]), now: t0)
        let out = tracker.apply(.statusChanged(pane: "w1:p1", agent: "claude", status: "idle", title: nil), now: t1)
        #expect(out.events.count == 2)
        #expect(out.events.last == .turnFinished(ref("w1:p1")))
        guard case .upserted(let info) = out.events.first else { Issue.record("no upsert"); return }
        #expect(info.status == .idle)
        #expect(info.changedAt == t1)
    }

    @Test func unfocusedTurnFinishesThroughDone() {
        var tracker = HerdrTracker(adapter: "herdr")
        _ = tracker.apply(HerdrSnapshot(agents: [pane("w1:p1", status: "working")]), now: t0)
        let out = tracker.apply(.statusChanged(pane: "w1:p1", agent: "claude", status: "done", title: nil), now: t1)
        #expect(out.events.last == .turnFinished(ref("w1:p1")))
        #expect(tracker.agents["w1:p1"]?.status == .done)
        // Seen: done → idle is not another turn.
        let seen = tracker.apply(.statusChanged(pane: "w1:p1", agent: "claude", status: "idle", title: nil), now: t1)
        #expect(!seen.events.contains(.turnFinished(ref("w1:p1"))))
    }

    @Test func aTurnMissedWhileDisconnectedIsCelebratedOnReconcile() {
        var tracker = HerdrTracker(adapter: "herdr")
        _ = tracker.apply(HerdrSnapshot(agents: [pane("w1:p1", status: "working")]), now: t0)
        let events = tracker.apply(HerdrSnapshot(agents: [pane("w1:p1", status: "done")]), now: t1)
        #expect(events.last == .turnFinished(ref("w1:p1")))
    }

    @Test func emptyTitleKeepsThePreviousOne() {
        var tracker = HerdrTracker(adapter: "herdr")
        _ = tracker.apply(HerdrSnapshot(agents: [pane("w1:p1", title: "Fix the bug")]), now: t0)
        let out = tracker.apply(.paneUpdated(pane("w1:p1", title: "  ")), now: t1)
        #expect(out.events.isEmpty)
        #expect(tracker.agents["w1:p1"]?.title == "Fix the bug")

        let renamed = tracker.apply(.paneUpdated(pane("w1:p1", status: nil, title: "Write tests")), now: t1)
        guard case .upserted(let info) = renamed.events.first else { Issue.record("no upsert"); return }
        #expect(info.title == "Write tests")
        #expect(info.status == .idle)
    }

    @Test func closedAndExitedPanesAreRemoved() {
        var tracker = HerdrTracker(adapter: "herdr")
        _ = tracker.apply(HerdrSnapshot(agents: [pane("w1:p1"), pane("w1:p2")]), now: t0)
        #expect(tracker.apply(.paneRemoved("w1:p1"), now: t1).events == [.removed(ref("w1:p1"))])
        #expect(tracker.apply(.paneRemoved("w9:p9"), now: t1).events.isEmpty, "not an agent pane")
        #expect(tracker.agentPanes == ["w1:p2"])
    }

    @Test func newAgentsNeedASnapshot() {
        var tracker = HerdrTracker(adapter: "herdr")
        _ = tracker.apply(HerdrSnapshot(agents: [pane("w1:p1")]), now: t0)
        #expect(tracker.apply(.agentDetected(pane: "w2:p1", agent: "codex"), now: t1).needsReconcile)
        #expect(tracker.apply(.paneCreated(pane("w2:p1", agent: nil)), now: t1).needsReconcile)
        #expect(tracker.apply(.statusChanged(pane: "w2:p1", agent: "codex", status: "working", title: nil), now: t1).needsReconcile)
        #expect(tracker.apply(.paneUpdated(pane("w2:p1", agent: "codex")), now: t1).needsReconcile)
        #expect(!tracker.apply(.paneUpdated(pane("w2:p1", agent: nil)), now: t1).needsReconcile, "a plain shell")
    }

    @Test func agentLeavingItsPaneNeedsASnapshot() {
        var tracker = HerdrTracker(adapter: "herdr")
        _ = tracker.apply(HerdrSnapshot(agents: [pane("w1:p1")]), now: t0)
        let out = tracker.apply(.statusChanged(pane: "w1:p1", agent: nil, status: "unknown", title: nil), now: t1)
        #expect(out.needsReconcile)
        #expect(out.events.isEmpty)
    }

    @Test func focusMoves() {
        var tracker = HerdrTracker(adapter: "herdr")
        _ = tracker.apply(HerdrSnapshot(focusedPaneID: "w1:p1", agents: [pane("w1:p1"), pane("w1:p2")]), now: t0)
        let out = tracker.apply(.paneFocused("w1:p2"), now: t1)
        let focused = out.events.compactMap { if case .upserted(let info) = $0 { (info.ref.localID, info.isFocused) } else { nil } }
        #expect(focused.map(\.0) == ["w1:p1", "w1:p2"])
        #expect(focused.map(\.1) == [false, true])
        #expect(tracker.apply(.paneFocused("w9:p9"), now: t1).events.count == 1, "only p2 loses focus")
    }

    @Test func tabRenamesRenameTheirAgents() {
        var tracker = HerdrTracker(adapter: "herdr")
        _ = tracker.apply(HerdrSnapshot(agents: [pane("w1:p1", tab: "w1:t1"), pane("w1:p2", tab: "w1:t2")],
                                        tabs: [.init(tabID: "w1:t1", label: "1"), .init(tabID: "w1:t2", label: "Docs")]), now: t0)
        let out = tracker.apply(.tabRenamed(tab: "w1:t1", label: "Nocchi"), now: t1)
        #expect(out.events.count == 1)
        #expect(tracker.agents["w1:p1"]?.name == "Nocchi")
        #expect(tracker.agents["w1:p2"]?.name == "Docs")
    }
}
