import Foundation
import NocchiCore
import Testing
@testable import NocchiHerdr

@Test func targetsHerdrProtocol22() {
    #expect(Herdr.supportedProtocol == 22)
}

@Test func resolvesSocketPaths() {
    let home = URL(fileURLWithPath: "/Users/me")
    #expect(Herdr.socketPath(home: home) == "/Users/me/.config/herdr/herdr.sock")
    #expect(Herdr.socketPath(session: "work", home: home) == "/Users/me/.config/herdr/sessions/work/herdr.sock")
    #expect(Herdr.socketPath(override: "/tmp/h.sock", session: "work", home: home) == "/tmp/h.sock")
    #expect(Herdr.socketPath(override: "", session: "", home: home) == "/Users/me/.config/herdr/herdr.sock")
}

/// Lines recorded from Herdr 0.9.0.
@Suite struct HerdrEventDecodingTests {
    func decode(_ line: String) -> HerdrEvent? { HerdrEvent.decode(Data(line.utf8)) }

    @Test func perPaneStatusChangeIsDottedAndFlat() {
        let event = decode(#"{"data":{"agent":"claude","agent_status":"done","pane_id":"w1:p1","workspace_id":"w1"},"event":"pane.agent_status_changed"}"#)
        #expect(event == .statusChanged(pane: "w1:p1", agent: "claude", status: "done", title: nil))
    }

    @Test func globalPaneEventsNestThePane() {
        let event = decode(#"{"data":{"pane":{"agent_status":"unknown","cwd":"/private/tmp","focused":true,"pane_id":"w3:p1","tab_id":"w3:t1","terminal_title":"My Title","terminal_title_stripped":"My Title","workspace_id":"w3"},"type":"pane_updated"},"event":"pane_updated"}"#)
        #expect(event == .paneUpdated(HerdrPane(paneID: "w3:p1", workspaceID: "w3", tabID: "w3:t1", agentStatus: "unknown", cwd: "/private/tmp", title: "My Title", focused: true)))
    }

    @Test func globalEventsWithFlatData() {
        #expect(decode(#"{"data":{"pane_id":"w2:p1","type":"pane_closed","workspace_id":"w2"},"event":"pane_closed"}"#) == .paneRemoved("w2:p1"))
        #expect(decode(#"{"data":{"pane_id":"w3:p1","type":"pane_exited","workspace_id":"w3"},"event":"pane_exited"}"#) == .paneRemoved("w3:p1"))
        #expect(decode(#"{"data":{"agent":"codex","pane_id":"w2:p1","type":"pane_agent_detected","workspace_id":"w2"},"event":"pane_agent_detected"}"#) == .agentDetected(pane: "w2:p1", agent: "codex"))
        #expect(decode(#"{"data":{"pane_id":"w2:p1","type":"pane_focused","workspace_id":"w2"},"event":"pane_focused"}"#) == .paneFocused("w2:p1"))
        #expect(decode(#"{"data":{"label":"Renamed","tab_id":"w1:t1","type":"tab_renamed","workspace_id":"w1"},"event":"tab_renamed"}"#) == .tabRenamed(tab: "w1:t1", label: "Renamed"))
    }

    @Test func bothSpellingsOfEveryEvent() {
        #expect(decode(#"{"data":{"pane_id":"w1:p1"},"event":"pane.closed"}"#) == .paneRemoved("w1:p1"))
        #expect(decode(#"{"data":{"pane":{"pane_id":"w1:p1","agent_status":"idle","agent":"pi"}},"event":"pane_agent_status_changed"}"#)
            == .statusChanged(pane: "w1:p1", agent: "pi", status: "idle", title: nil))
    }

    @Test func ignoresAcksAndUnknownEvents() {
        #expect(decode(#"{"id":"s1","result":{"type":"subscription_started"}}"#) == nil)
        #expect(decode(#"{"data":{"type":"workspace_focused","workspace_id":"w2"},"event":"workspace_focused"}"#) == nil)
        #expect(decode("not json") == nil)
    }
}

@Suite struct HerdrAdapterTests {
    @Test func reportsUnavailableRightAwayWhenHerdrIsntRunning() async {
        let adapter = HerdrAdapter(socketPath: "/tmp/nocchi-no-such-herdr.sock")
        let recorder = EventRecorder(adapter.events())
        defer { recorder.stop() }
        let events = await recorder.wait(.seconds(2)) { $0.count >= 2 }
        guard events.count >= 2, case .connection(.unavailable(let reason)) = events[0] else {
            Issue.record("expected .unavailable first, got \(events)")
            return
        }
        #expect(reason.contains("isn't running"))
        #expect(events[1] == .snapshot([]))
    }

    @Test func agentNamesFollowHerdrsRules() {
        #expect(HerdrAdapter.agentName("nocchi") == "nocchi")
        #expect(HerdrAdapter.agentName("My Project!") == "my-project-")
        #expect(HerdrAdapter.agentName("2048 game") == "game")
        #expect(HerdrAdapter.agentName("") == "agent")
        #expect(HerdrAdapter.agentName(String(repeating: "a", count: 40)).count == 32)
    }

    @Test func linesSurviveSplitMultibyteCharacters() throws {
        var fds: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
        defer { close(fds[1]) }
        let connection = HerdrConnection(fileDescriptor: fds[0])
        let bytes = Array(#"{"title":"✳ café"}"#.utf8) + [0x0A]
        let split = bytes.firstIndex(of: 0xE2)! + 1   // inside "✳"
        _ = bytes[..<split].withUnsafeBytes { write(fds[1], $0.baseAddress!, $0.count) }
        _ = bytes[split...].withUnsafeBytes { write(fds[1], $0.baseAddress!, $0.count) }
        let line = try #require(try connection.readLine())
        #expect(String(decoding: line, as: UTF8.self) == #"{"title":"✳ café"}"#)
    }
}
