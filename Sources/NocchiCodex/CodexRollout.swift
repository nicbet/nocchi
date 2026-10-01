import Foundation

/// What one line of a Codex rollout log (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`) says.
public enum CodexRolloutEvent: Equatable, Sendable {
    case session(id: String, cwd: String?)
    case turnStarted
    /// With the turn's final message, when it has one.
    case turnCompleted(lastMessage: String?)
    /// Interrupted by the user.
    case turnAborted
    /// A tool call, as a short phrase ("Editing main.go", "Running rg --files").
    case step(String)
    /// The agent talking to the user (commentary or the final answer).
    case message(String)

    /// Parses one rollout line. Nil for lines that don't matter (token counts, reasoning, …).
    public static func parse(_ line: Data) -> CodexRolloutEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = object["payload"] as? [String: Any] else { return nil }
        switch (object["type"] as? String, payload["type"] as? String) {
        case ("session_meta", _):
            guard let id = payload["session_id"] as? String ?? payload["id"] as? String else { return nil }
            return .session(id: id, cwd: payload["cwd"] as? String)
        case ("event_msg", "task_started"):
            return .turnStarted
        case ("event_msg", "task_complete"):
            return .turnCompleted(lastMessage: (payload["last_agent_message"] as? String).flatMap(opening))
        case ("event_msg", "turn_aborted"):
            return .turnAborted
        case ("event_msg", "item_completed"):
            return (payload["item"] as? [String: Any]).flatMap(item)
        default:
            return nil
        }
    }

    static func item(_ item: [String: Any]) -> CodexRolloutEvent? {
        switch item["type"] as? String {
        case "CommandExecution":
            if let parsed = (item["parsed_cmd"] as? [[String: Any]])?.first,
               let phrase = parsedCommand(parsed) { return .step(phrase) }
            guard let command = item["command"] as? [String] else { return nil }
            // ["zsh", "-lc", "<script>"]: the script is what ran.
            return .step("Running " + short(command.last ?? "", 40))
        case "FileChange":
            guard let changes = item["changes"] as? [String: Any], let path = changes.keys.sorted().first else { return nil }
            let kind = (changes[path] as? [String: Any])?["type"] as? String
            let verb = kind == "add" ? "Creating" : kind == "delete" ? "Deleting" : "Editing"
            let more = changes.count > 1 ? " and \(changes.count - 1) more" : ""
            return .step("\(verb) \((path as NSString).lastPathComponent)\(more)")
        case "McpToolCall":
            guard let server = item["server"] as? String, let tool = item["tool"] as? String else { return nil }
            return .step("\(server): \(tool.replacingOccurrences(of: "_", with: " "))")
        case "Extension":
            if let query = item["query"] as? String, !query.isEmpty { return .step("Searching the web for “\(short(query, 40))”") }
            return nil
        case "AgentMessage":
            let text = (item["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined(separator: "\n")
            return text.flatMap(opening).map(CodexRolloutEvent.message)
        default:
            return nil
        }
    }

    /// Codex's own reading of a command: `{"type": "read", "name": "main.go"}`, `search`, `list_files`.
    static func parsedCommand(_ parsed: [String: Any]) -> String? {
        switch parsed["type"] as? String {
        case "read": return (parsed["name"] as? String).map { "Reading \(($0 as NSString).lastPathComponent)" }
        case "search": return (parsed["query"] as? String).map { "Searching for “\(short($0, 40))”" }
        case "list_files": return "Listing files"
        default: return (parsed["cmd"] as? String).map { "Running " + short($0, 40) }
        }
    }

    static func short(_ text: String, _ limit: Int) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.count > limit ? String(line.prefix(limit - 1)) + "…" : line
    }

    /// The first line of a message, without markdown, cut to whole sentences within 160 characters.
    static func opening(_ text: String) -> String? {
        guard var line = text.split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty && !$0.hasPrefix("```") }) else { return nil }
        for prefix in ["#### ", "### ", "## ", "# ", "- ", "* ", "> "] where line.hasPrefix(prefix) { line.removeFirst(prefix.count) }
        for marker in ["**", "__", "`"] { line = line.replacingOccurrences(of: marker, with: "") }
        if line.count > 160 {
            let head = String(line.prefix(160))
            line = head.range(of: ". ", options: .backwards).map { String(head[..<$0.lowerBound]) + "." } ?? head + "…"
        }
        return line.isEmpty ? nil : line
    }
}
