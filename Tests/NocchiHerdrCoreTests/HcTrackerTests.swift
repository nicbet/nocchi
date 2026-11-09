import Foundation
import NocchiCore
import Testing
@testable import NocchiHerdrCore

/// Lines as herdr-core 0.1.19 sends them (captured from a real core).
enum Fixture {
    static let claudeDone = #"{"address":"t5","argv":["/opt/homebrew/bin/zsh","-l"],"cols":162,"cwd":"/tmp/project","exit_code":null,"foreground":{"argv":["claude"],"cwd":"/tmp/project","name":"2.1.319","pid":4242},"keep":true,"labels":{"herdr.seen":"10","herdr.space":"sp2","herdr.tab":"tb2","where":"~ / 1"},"name":null,"pid":4241,"state":"live","status":{"app":"claude-code","state":"done"},"status_ms":1700000000000,"title":"Fix the login bug","turn":10}"#
    static let shell = #"{"address":"t1","argv":["/opt/homebrew/bin/zsh","-l"],"cwd":"/Users/me","foreground":{"argv":["/opt/homebrew/bin/zsh","-l"],"cwd":"/Users/me","name":"zsh","pid":4240},"labels":{},"state":"live","status":null,"title":"","turn":0}"#
    static let finished = #"{"address":"t2","cwd":"/tmp","exit_code":1,"labels":{},"state":"finished","status":{"app":"claude-code","state":"done"},"title":"","turn":3}"#

    static func event(_ terminal: String, _ type: String, _ data: String, seq: Int = 1) -> Data {
        Data(#"{"jsonrpc":"2.0","method":"event","params":{"data":\#(data),"seq":\#(seq),"terminal":"\#(terminal)","type":"\#(type)"}}"#.utf8)
    }

    static func terminal(_ json: String) -> HcTerminal {
        try! JSONDecoder().decode(HcTerminal.self, from: Data(json.utf8))
    }

    static let layout = #"{"spaces":[{"folder":"/Users/me","id":"sp1","name":"Demo","tabs":[{"id":"tb1","name":"","root":{"children":[{"content":{"terminal":"t1"},"id":"p1","size":{"weight":0.5},"type":"block"},{"content":{"terminal":"t5"},"id":"p2","size":{"weight":0.5},"type":"block"}],"id":"tb1","type":"row"}}]},{"folder":"/x","id":"sp2","name":"","tabs":[{"id":"tb2","name":"review","root":{"content":{"terminal":"t7"},"id":"p3","type":"block"}},{"id":"tb3","name":"2","root":{"content":{"terminal":"t8"},"id":"p4","type":"block"}}]}]}"#
}

struct HcTrackerTests {
    let now = Date()

    func event(_ terminal: String, _ type: String, _ data: String) -> HcEvent {
        HcEvent.decode(Fixture.event(terminal, type, data))!
    }

    @Test func snapshotKeepsOnlyLiveTerminalsThatReport() {
        var tracker = HcTracker(adapter: "hc")
        let events = tracker.apply([Fixture.claudeDone, Fixture.shell, Fixture.finished].map(Fixture.terminal), now: now)
        guard case .snapshot(let agents) = events.first else { Issue.record("\(events)"); return }
        #expect(agents.map(\.ref.localID) == ["t5"])
        let agent = agents[0]
        #expect(agent.kind == .claude)
        // Turn 10 finished and herdr-app has shown turn 10: read.
        #expect(agent.status == .idle)
        #expect(agent.title == "Fix the login bug")
        #expect(agent.cwd?.path == "/tmp/project")
    }

    @Test func followsATurnWithoutFlicker() {
        var tracker = HcTracker(adapter: "hc")
        _ = tracker.apply([Fixture.terminal(#"{"address":"t7","cwd":"/tmp","labels":{},"state":"live","status":null,"turn":0}"#)], now: now)
        let ref = AgentRef(adapter: "hc", localID: "t7")

        var seen: [AgentStatus] = []
        var finished = 0
        for (type, data) in [
            ("status", #"{"records":{},"reported":true,"status":{"app":"fake","state":"working"}}"#),
            ("status", #"{"records":{},"reported":true,"status":{"app":"fake","state":"done"}}"#),
            ("turn", #"{"state":"done","turn":1}"#),
            ("labels", #"{"labels":{"herdr.seen":"1"}}"#),
        ] {
            for out in tracker.apply(event("t7", type, data), now: now) {
                if case .upserted(let info) = out { seen.append(info.status) }
                if case .turnFinished(ref) = out { finished += 1 }
            }
        }
        #expect(seen == [.working, .done, .idle])
        #expect(finished == 1)
    }

    @Test func blockedAndError() {
        var tracker = HcTracker(adapter: "hc")
        _ = tracker.apply([Fixture.terminal(Fixture.claudeDone)], now: now)
        var out = tracker.apply(event("t5", "status", #"{"status":{"app":"claude-code","kind":"permission","state":"blocked"}}"#), now: now)
        #expect(tracker.agents["t5"]?.status == .blocked)
        out = tracker.apply(event("t5", "status", #"{"status":{"app":"claude-code","state":"error","msg":"boom"}}"#), now: now)
        #expect(out.count == 1)
        #expect(tracker.agents["t5"]?.status == .error("boom"))
    }

    @Test func agentLeavingItsShellOrTheTerminalEndingRemovesIt() {
        var tracker = HcTracker(adapter: "hc")
        _ = tracker.apply([Fixture.terminal(Fixture.claudeDone)], now: now)
        let ref = AgentRef(adapter: "hc", localID: "t5")
        #expect(tracker.apply(event("t5", "status", #"{"records":{},"reported":true,"status":null}"#), now: now) == [.removed(ref)])
        // The shell's own events don't bring it back.
        #expect(tracker.apply(event("t5", "title", #"{"title":""}"#), now: now).isEmpty)
        // An agent started again in the same terminal comes back.
        let again = tracker.apply(event("t5", "status", #"{"status":{"app":"codex","state":"idle"}}"#), now: now)
        guard case .upserted(let info) = again.first else { Issue.record("\(again)"); return }
        #expect(info.kind == .codex)
        #expect(tracker.apply(event("t5", "finished", #"{"exit_code":0,"reason":"exited"}"#), now: now) == [.removed(ref)])
        #expect(tracker.apply(event("t5", "removed", "{}"), now: now).isEmpty)
    }

    @Test func createdTerminalThatReportsAppears() {
        var tracker = HcTracker(adapter: "hc")
        _ = tracker.apply([], now: now)
        let created = HcEvent.decode(Fixture.event("t9", "created", #"{"address":"t9","cwd":"/tmp","labels":{},"state":"live","status":null,"turn":0}"#))
        #expect(created != nil)
        #expect(tracker.apply(created!, now: now).isEmpty)
        let out = tracker.apply(event("t9", "status", #"{"status":{"app":"pi","state":"idle"}}"#), now: now)
        guard case .upserted(let info) = out.first else { Issue.record("\(out)"); return }
        #expect(info.kind == .pi)
        #expect(info.status == .idle)
    }

    @Test func claudeSessionComesFromItsProcess() {
        var tracker = HcTracker(adapter: "hc") { $0 == 4242 ? "session-a" : nil }
        _ = tracker.apply([Fixture.terminal(Fixture.claudeDone)], now: now)
        #expect(tracker.agents["t5"]?.sessionID == "session-a")
    }

    @Test func emptyTitleKeepsThePreviousOne() {
        var tracker = HcTracker(adapter: "hc")
        _ = tracker.apply([Fixture.terminal(Fixture.claudeDone)], now: now)
        #expect(tracker.apply(event("t5", "title", #"{"title":""}"#), now: now).isEmpty)
        #expect(tracker.agents["t5"]?.title == "Fix the login bug")
    }

    @Test func namesComeFromTheLayout() throws {
        let layout = try JSONDecoder().decode(HerdrAppLayout.self, from: Data(Fixture.layout.utf8))
        #expect(layout.names == ["t1": "Demo", "t5": "Demo", "t7": "review"])

        var tracker = HcTracker(adapter: "hc")
        _ = tracker.apply([Fixture.terminal(Fixture.claudeDone)], now: now)
        let out = tracker.setLayout(layout, now: now)
        guard case .upserted(let info) = out.first else { Issue.record("\(out)"); return }
        #expect(info.name == "Demo")
        #expect(tracker.setLayout(nil, now: now).count == 1)
        #expect(tracker.agents["t5"]?.name == nil)
    }

    @Test func decodesNotifications() {
        #expect(HcEvent.decode(Data(#"{"jsonrpc":"2.0","method":"heartbeat","params":{"seq":263}}"#.utf8)) == .heartbeat)
        #expect(HcEvent.decode(Data(#"{"jsonrpc":"2.0","method":"event","params":{"data":{"name":"herdr-app","version":31},"seq":264,"type":"doc"}}"#.utf8)) == .doc(name: "herdr-app"))
        #expect(HcEvent.decode(Fixture.event("t5", "size", #"{"cols":1,"rows":2}"#)) == nil)
        #expect(HcEvent.decode(Data(#"{"id":1,"jsonrpc":"2.0","result":{}}"#.utf8)) == nil)
        #expect(HcEvent.decode(Fixture.event("t5", "foreground", #"{"cwd":"/x","name":"zsh","pid":1}"#)) == .foreground(terminal: "t5", cwd: "/x", pid: 1))
    }
}
