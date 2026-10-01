import Foundation

/// Adds and removes nocchi's hooks in Claude Code's and Codex's settings. Opt-in, from the menu.
///
/// Both use the same shape: `{"hooks": {"<Event>": [{"matcher": "…", "hooks": [{"type": "command",
/// "command": "…"}]}]}}`. nocchi's entries are recognised by their `nocchi-hook` command, so
/// installing is idempotent, removing takes out exactly nocchi's entries, and other hooks (Herdr's,
/// your own) are left alone. Every file is backed up before its first change.
public enum HookInstaller {
    public enum Agent: String, CaseIterable, Sendable {
        case claude, codex

        public var title: String { self == .claude ? "Claude Code" : "Codex" }

        /// The settings file nocchi edits.
        public func settingsFile(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
            switch self {
            case .claude: home.appending(path: ".claude/settings.json")
            case .codex: home.appending(path: ".codex/hooks.json")
            }
        }

        /// The events nocchi listens to: lifecycle and status only (content comes from the logs).
        var events: [String] {
            switch self {
            case .claude: ["SessionStart", "UserPromptSubmit", "PostToolUse", "PermissionRequest", "Notification",
                           "Stop", "StopFailure", "SessionEnd"]
            case .codex: ["SessionStart", "UserPromptSubmit", "PostToolUse", "PermissionRequest", "Stop", "Interrupt"]
            }
        }

        /// One hook entry. Claude runs it asynchronously, so it never waits on nocchi.
        func entry(command: String) -> [String: Any] {
            var hook: [String: Any] = ["type": "command", "command": command, "timeout": 5]
            if self == .claude { hook["async"] = true }
            return ["matcher": "", "hooks": [hook]]
        }
    }

    /// Where the hook binary lives for hooks to call: outside the app, so moving the app doesn't
    /// break them.
    public static func hookBinary(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: "Library/Application Support/nocchi/bin/nocchi-hook")
    }

    static func command(for agent: Agent, binary: URL) -> String {
        "'\(binary.path)' \(agent.rawValue)"
    }

    // MARK: Pure edits

    /// Whether `settings` has nocchi's hooks.
    static func isInstalled(in settings: [String: Any]) -> Bool {
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        return hooks.values.contains { groups in
            (groups as? [[String: Any]] ?? []).contains(where: isOurs)
        }
    }

    /// `settings` with nocchi's hooks for `agent` (replacing any earlier ones).
    static func installing(_ agent: Agent, command: String, into settings: [String: Any]) -> [String: Any] {
        var settings = removing(from: settings)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in agent.events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups.append(agent.entry(command: command))
            hooks[event] = groups
        }
        settings["hooks"] = hooks
        return settings
    }

    /// `settings` without nocchi's hooks; events and groups left empty are dropped.
    static func removing(from settings: [String: Any]) -> [String: Any] {
        var settings = settings
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept = groups.compactMap { group -> [String: Any]? in
                guard let entries = group["hooks"] as? [[String: Any]] else { return group }
                let others = entries.filter { !(($0["command"] as? String) ?? "").contains("nocchi-hook") }
                if others.count == entries.count { return group }
                guard !others.isEmpty else { return nil }
                var group = group
                group["hooks"] = others
                return group
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        return settings
    }

    private static func isOurs(_ group: [String: Any]) -> Bool {
        (group["hooks"] as? [[String: Any]] ?? []).contains { (($0["command"] as? String) ?? "").contains("nocchi-hook") }
    }

    /// Codex runs hooks only with `[features] hooks = true` in `config.toml`. Returns the file's text
    /// with it set, or nil when it already is.
    static func enablingCodexHooks(in config: String) -> String? {
        var lines = config.components(separatedBy: "\n")
        var section: String?
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { section = trimmed; continue }
            guard section == "[features]", trimmed.hasPrefix("hooks"), trimmed.contains("=") else { continue }
            if trimmed.replacingOccurrences(of: " ", with: "") == "hooks=true" { return nil }
            lines[index] = "hooks = true"
            return lines.joined(separator: "\n")
        }
        if let header = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[features]" }) {
            lines.insert("hooks = true", at: header + 1)
            return lines.joined(separator: "\n")
        }
        return config + (config.hasSuffix("\n") || config.isEmpty ? "" : "\n") + "\n[features]\nhooks = true\n"
    }

    // MARK: Files

    public static func isInstalled(_ agent: Agent, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        (try? read(agent.settingsFile(home: home))).map(isInstalled(in:)) ?? false
    }

    /// Installs nocchi's hooks for `agent`: the hook binary (copied from `bundledBinary`), the
    /// settings entries, and for Codex the feature flag. Returns the files it changed.
    @discardableResult
    public static func install(_ agent: Agent, bundledBinary: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> [URL] {
        let binary = hookBinary(home: home)
        try updateBinary(from: bundledBinary, to: binary)
        let file = agent.settingsFile(home: home)
        var changed = [file]
        let settings = try read(file)
        try write(installing(agent, command: command(for: agent, binary: binary), into: settings), to: file)
        if agent == .codex {
            let config = home.appending(path: ".codex/config.toml")
            let text = (try? String(contentsOf: config, encoding: .utf8)) ?? ""
            if let enabled = enablingCodexHooks(in: text) {
                try backup(config)
                try enabled.write(to: config, atomically: true, encoding: .utf8)
                changed.append(config)
            }
        }
        return changed
    }

    /// Removes nocchi's hooks for `agent` (the feature flag stays: other hooks may need it).
    public static func uninstall(_ agent: Agent, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        let file = agent.settingsFile(home: home)
        let settings = try read(file)
        guard isInstalled(in: settings) else { return }
        try write(removing(from: settings), to: file)
    }

    /// Keeps the hook binary in step with the app's (called at launch when hooks are installed).
    public static func updateBinary(from bundled: URL, to binary: URL) throws {
        let fm = FileManager.default
        if let installed = try? Data(contentsOf: binary), let current = try? Data(contentsOf: bundled), installed == current { return }
        try fm.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: binary)
        try fm.copyItem(at: bundled, to: binary)
    }

    static func read(_ file: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        let data = try Data(contentsOf: file)
        guard !data.isEmpty else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: file.path])
        }
        return object
    }

    static func write(_ settings: [String: Any], to file: URL) throws {
        try backup(file)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try (data + Data("\n".utf8)).write(to: file, options: .atomic)
    }

    /// `settings.json` → `settings.json.nocchi-backup-<date>`, once per change.
    static func backup(_ file: URL) throws {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let copy = file.deletingLastPathComponent().appending(path: file.lastPathComponent + ".nocchi-backup-" + stamp)
        if !FileManager.default.fileExists(atPath: copy.path) { try FileManager.default.copyItem(at: file, to: copy) }
    }
}
