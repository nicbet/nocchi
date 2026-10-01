import Foundation
import NocchiTerminals
import Testing
@testable import NocchiCodex

@Suite struct CodexDiscoveryTests {
    @Test func onlyTheInteractiveCLICounts() {
        let table = ProcessTable.parse("""
            100  1 ttys001  /Users/me/.local/bin/codex
            101  1 ttys002  codex resume 01a0
            102  1 ??       /Users/me/.local/bin/codex app-server --listen
            103  1 ??       codex exec say hi
            104  1 ??       /Applications/ChatGPT.app/Contents/Resources/codex app-server
            105  1 ttys003  /bin/zsh
        """)
        let cli = table.entries.values.filter(CodexDiscovery.isCLI).map(\.pid).sorted()
        #expect(cli == [100, 101])
    }

    @Test func readsCwdAndOpenFilesFromLsof() {
        let output = "p100\nfcwd\nn/Users/me/code/api\nftxt\nn/Users/me/.local/bin/codex\nf23\nn/Users/me/.codex/sessions/2026/10/01/rollout-x.jsonl\n"
        let files = CodexDiscovery.parseLsof(output)
        #expect(files.cwd == "/Users/me/code/api")
        #expect(files.paths.contains("/Users/me/.codex/sessions/2026/10/01/rollout-x.jsonl"))
    }

    @Test func sessionMetaAndTailing() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "rollout-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        try (#"{"type":"session_meta","payload":{"session_id":"01a0","cwd":"/r/api"}}"# + "\n"
            + #"{"type":"event_msg","payload":{"type":"task_started"}}"# + "\n").write(to: file, atomically: true, encoding: .utf8)
        let meta = try #require(CodexDiscovery.sessionMeta(file))
        #expect(meta.id == "01a0")
        #expect(meta.cwd == "/r/api")

        var tails = RolloutTails()
        #expect(tails.start("01a0", at: file) == [.session(id: "01a0", cwd: "/r/api"), .turnStarted])
        #expect(tails.read().isEmpty)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((#"{"type":"event_msg","payload":{"type":"task_complete","last_agent_message":"Done."}}"# + "\n").utf8))
        try handle.close()
        let new = tails.read()
        #expect(new.count == 1)
        #expect(new.first?.1 == [.turnCompleted(lastMessage: "Done.")])
    }
}
