import Foundation

/// What a Claude Code agent is doing, from one line of its session transcript
/// (`~/.claude/projects/<project>/<session>.jsonl`). Only the main conversation counts:
/// subagent (sidechain) lines are skipped.
public enum ClaudeActivity {
    /// A short phrase for the tool call on `line` ("Editing Model.swift"), or nil if the line isn't
    /// one. With several tool calls in one message, the last one wins.
    public static func phrase(forLine line: Data) -> String? {
        guard let entry = try? JSONDecoder().decode(Entry.self, from: line),
              entry.type == "assistant", entry.isSidechain != true else { return nil }
        return entry.message?.content?.compactMap(\.toolUse).last.flatMap(phrase)
    }

    /// The opening of the agent's text on `line`, cleaned of markdown: the line it starts with,
    /// cut to its first sentence when long. Nil if the line has no main-thread text.
    public static func message(forLine line: Data) -> String? {
        guard let entry = try? JSONDecoder().decode(Entry.self, from: line),
              entry.type == "assistant", entry.isSidechain != true,
              let text = entry.message?.content?.compactMap(\.text).last else { return nil }
        return opening(of: text)
    }

    static func opening(of text: String) -> String? {
        let firstLine = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("```") }
        guard var line = firstLine else { return nil }
        for prefix in ["#### ", "### ", "## ", "# ", "- ", "* ", "> "] where line.hasPrefix(prefix) {
            line.removeFirst(prefix.count)
        }
        for marker in ["**", "__", "`"] { line = line.replacingOccurrences(of: marker, with: "") }
        // Long: keep whole sentences that fit.
        let limit = 160
        if line.count > limit {
            let head = String(line.prefix(limit))
            if let end = head.range(of: ". ", options: .backwards) {
                line = String(head[..<end.lowerBound]) + "."
            } else {
                line = head + "…"
            }
        }
        return line.isEmpty ? nil : line
    }

    /// The session's latest `ai-title` (what Claude puts in the terminal title), from the end of
    /// its transcript.
    public static func latestTitle(session: String, root: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/projects")) -> String? {
        let name = "\(session).jsonl"
        let projects = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        guard let file = projects.lazy.map({ $0.appending(path: name) }).first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > 1 << 20 ? size - (1 << 20) : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return nil }
        for line in data.split(separator: 0x0A).reversed() where line.count < 4096 {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["type"] as? String == "ai-title", let title = object["aiTitle"] as? String, !title.isEmpty else { continue }
            return title
        }
        return nil
    }

    static func phrase(_ tool: ToolUse) -> String? {
        let input = tool.input ?? [:]
        func file(_ key: String = "file_path") -> String? {
            input[key].flatMap { $0.isEmpty ? nil : ($0 as NSString).lastPathComponent }
        }
        func short(_ text: String, _ limit: Int = 60) -> String {
            let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
            return line.count > limit ? String(line.prefix(limit - 1)) + "…" : line
        }
        switch tool.name {
        case "Edit", "MultiEdit": return file().map { "Editing \($0)" } ?? "Editing"
        case "Write": return file().map { "Writing \($0)" } ?? "Writing"
        case "Read": return file().map { "Reading \($0)" } ?? "Reading"
        case "NotebookEdit": return file("notebook_path").map { "Editing \($0)" } ?? "Editing a notebook"
        case "Bash":
            if let description = input["description"], !description.isEmpty { return short(description) }
            return input["command"].map { "Running \(short($0, 40))" } ?? "Running a command"
        case "Grep": return input["pattern"].map { "Searching for “\(short($0, 40))”" } ?? "Searching"
        case "Glob": return input["pattern"].map { "Finding \(short($0, 40))" } ?? "Finding files"
        case "WebFetch": return input["url"].flatMap { URL(string: $0)?.host }.map { "Reading \($0)" } ?? "Reading the web"
        case "WebSearch": return input["query"].map { "Searching the web for “\(short($0, 40))”" } ?? "Searching the web"
        case "Task", "Agent": return input["description"].map { short($0) } ?? "Delegating to a subagent"
        case "TodoWrite": return "Updating the plan"
        case "ToolSearch", "ExitPlanMode", "EnterPlanMode": return nil
        default:
            // MCP tools are named mcp__<server>__<tool>: "xpo: add note".
            let parts = tool.name.components(separatedBy: "__")
            guard parts.count >= 3, parts[0] == "mcp" else { return "Using \(tool.name)" }
            return "\(parts[1]): \(parts[2...].joined(separator: " ").replacingOccurrences(of: "_", with: " "))"
        }
    }

    // MARK: Transcript shape (only what we read)

    struct Entry: Decodable {
        var type: String?
        var isSidechain: Bool?
        var message: Message?
    }

    struct Message: Decodable {
        var content: [Content]?

        init(from decoder: Decoder) throws {
            // `content` is a string for plain user prompts.
            let c = try decoder.container(keyedBy: CodingKeys.self)
            content = try? c.decodeIfPresent([Content].self, forKey: .content)
        }
        private enum CodingKeys: String, CodingKey { case content }
    }

    struct Content: Decodable {
        var toolUse: ToolUse?
        var text: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let type = try c.decodeIfPresent(String.self, forKey: .type)
            if type == "text" {
                text = try c.decodeIfPresent(String.self, forKey: .text)
                return
            }
            guard type == "tool_use" else { return }
            let input = try? c.decodeIfPresent(Input.self, forKey: .input)
            toolUse = ToolUse(name: try c.decode(String.self, forKey: .name), input: input?.strings)
        }
        private enum CodingKeys: String, CodingKey { case type, name, input, text }
    }

    struct ToolUse {
        var name: String
        /// The input's string fields; others are dropped.
        var input: [String: String]?
    }

    private struct Input: Decodable {
        var strings: [String: String] = [:]

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            for key in c.allKeys {
                if let value = try? c.decode(String.self, forKey: key) { strings[key.stringValue] = value }
            }
        }
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
