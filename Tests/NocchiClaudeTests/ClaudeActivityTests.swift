import Foundation
import Testing
@testable import NocchiClaude

/// Lines shaped like Claude Code 2.x transcripts.
@Suite struct ClaudeActivityTests {
    func line(_ tool: String, _ input: String, sidechain: Bool = false) -> Data {
        Data(#"{"type":"assistant","isSidechain":\#(sidechain),"message":{"role":"assistant","content":[{"type":"text","text":"Now the tool."},{"type":"tool_use","id":"t1","name":"\#(tool)","input":\#(input)}]},"timestamp":"2026-10-01T09:05:15Z"}"#.utf8)
    }

    @Test func phrasesForCommonTools() {
        #expect(ClaudeActivity.phrase(forLine: line("Edit", #"{"file_path":"/a/b/Model.swift","old_string":"x","new_string":"y"}"#)) == "Editing Model.swift")
        #expect(ClaudeActivity.phrase(forLine: line("Write", #"{"file_path":"/a/upload.go","content":"…"}"#)) == "Writing upload.go")
        #expect(ClaudeActivity.phrase(forLine: line("Read", #"{"file_path":"/a/env.go","limit":40}"#)) == "Reading env.go")
        #expect(ClaudeActivity.phrase(forLine: line("Bash", #"{"command":"grep -n x","description":"Check Caddy host route paths"}"#)) == "Check Caddy host route paths")
        #expect(ClaudeActivity.phrase(forLine: line("Bash", #"{"command":"swift test --filter Herdr\nmore"}"#)) == "Running swift test --filter Herdr")
        #expect(ClaudeActivity.phrase(forLine: line("Grep", #"{"pattern":"func Hint"}"#)) == "Searching for “func Hint”")
        #expect(ClaudeActivity.phrase(forLine: line("WebFetch", #"{"url":"https://herdr.dev/docs","prompt":"x"}"#)) == "Reading herdr.dev")
        #expect(ClaudeActivity.phrase(forLine: line("Task", #"{"description":"Find Herdr event shapes","prompt":"…"}"#)) == "Find Herdr event shapes")
        #expect(ClaudeActivity.phrase(forLine: line("mcp__xpo__add_note", #"{"text":"x"}"#)) == "xpo: add note")
        #expect(ClaudeActivity.phrase(forLine: line("ToolSearch", #"{"query":"x"}"#)) == nil)
    }

    @Test func ignoresEverythingButMainThreadToolCalls() {
        #expect(ClaudeActivity.phrase(forLine: line("Edit", #"{"file_path":"/a/x.swift"}"#, sidechain: true)) == nil)
        #expect(ClaudeActivity.phrase(forLine: Data(#"{"type":"user","message":{"role":"user","content":"fix it"}}"#.utf8)) == nil)
        #expect(ClaudeActivity.phrase(forLine: Data(#"{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}"#.utf8)) == nil)
        #expect(ClaudeActivity.phrase(forLine: Data(#"{"type":"ai-title","aiTitle":"srv-4a777b"}"#.utf8)) == nil)
        #expect(ClaudeActivity.phrase(forLine: Data("not json".utf8)) == nil)
    }

    @Test func longCommandsAreShortened() throws {
        let phrase = try #require(ClaudeActivity.phrase(forLine: line("Bash", #"{"command":"python3 - <<'EOF' with a very very long heredoc that goes on and on"}"#)))
        #expect(phrase.count <= 48)
        #expect(phrase.hasSuffix("…"))
    }
}

@Suite struct ClaudeTranscriptsTests {
    func entry(_ file: String) -> String {
        #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/x/\#(file)"}}]}}"#
    }

    @Test func firstReadShowsTheLatestStepThenOnlyNewOnes() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "nocchi-transcripts-\(UUID().uuidString)")
        let project = root.appending(path: "-Users-me-repo")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = project.appending(path: "abc.jsonl")
        try (entry("a.swift") + "\n" + entry("b.swift") + "\n").write(to: file, atomically: true, encoding: .utf8)

        let transcripts = ClaudeTranscripts(root: root)
        #expect(await transcripts.newPhrases(session: "abc") == ["Editing b.swift"])
        #expect(await transcripts.newPhrases(session: "abc").isEmpty)

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        // A line arrives in two writes: nothing until it's complete.
        let next = entry("c.swift")
        try handle.write(contentsOf: Data(next.prefix(20).utf8))
        #expect(await transcripts.newPhrases(session: "abc").isEmpty)
        try handle.write(contentsOf: Data((next.dropFirst(20) + "\n" + entry("d.swift") + "\n").utf8))
        try handle.close()
        #expect(await transcripts.newPhrases(session: "abc") == ["Editing c.swift", "Editing d.swift"])
        #expect(await transcripts.newPhrases(session: "nope").isEmpty)
    }
}

@Suite struct ClaudeTranscriptsWindowTests {
    @Test func firstReadLooksPastHugeTrailingLines() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "nocchi-transcripts-\(UUID().uuidString)")
        let project = root.appending(path: "p")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/x/notes.md"}}]}}"#
        let image = #"{"type":"user","message":{"content":[{"type":"image","data":""# + String(repeating: "A", count: 600_000) + #""}]}}"#
        try (tool + "\n" + image + "\n").write(to: project.appending(path: "s.jsonl"), atomically: true, encoding: .utf8)
        #expect(await ClaudeTranscripts(root: root).newPhrases(session: "s") == ["Reading notes.md"])
    }
}
