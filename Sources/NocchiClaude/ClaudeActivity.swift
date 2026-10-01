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

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard try c.decodeIfPresent(String.self, forKey: .type) == "tool_use" else { return }
            let input = try? c.decodeIfPresent(Input.self, forKey: .input)
            toolUse = ToolUse(name: try c.decode(String.self, forKey: .name), input: input?.strings)
        }
        private enum CodingKeys: String, CodingKey { case type, name, input }
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
