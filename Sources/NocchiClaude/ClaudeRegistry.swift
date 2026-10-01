import Foundation

/// Claude Code's registry of running interactive sessions: `~/.claude/sessions/<pid>.json`, one
/// file per `claude` process, with its session, folder and a live `status` ("busy", "idle").
/// Enough to see every Claude session without hooks or any setup.
public struct ClaudeRegistryEntry: Equatable, Sendable {
    public var pid: Int32
    public var sessionID: String
    public var cwd: String?
    public var name: String?
    /// "busy", "idle", or whatever newer versions add.
    public var status: String?
    public var statusUpdatedAt: Date?

    public init(pid: Int32, sessionID: String, cwd: String? = nil, name: String? = nil, status: String? = nil, statusUpdatedAt: Date? = nil) {
        self.pid = pid
        self.sessionID = sessionID
        self.cwd = cwd
        self.name = name
        self.status = status
        self.statusUpdatedAt = statusUpdatedAt
    }

    /// Parses one registry file. Nil for anything but an interactive session (headless `claude -p`
    /// runs and other tools' helpers aren't agents you watch).
    public static func parse(_ data: Data) -> ClaudeRegistryEntry? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = object["pid"] as? Int, let session = object["sessionId"] as? String, !session.isEmpty,
              (object["kind"] as? String ?? "interactive") == "interactive" else { return nil }
        let updated = (object["statusUpdatedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return ClaudeRegistryEntry(pid: Int32(pid), sessionID: session, cwd: object["cwd"] as? String,
                                   name: object["name"] as? String, status: object["status"] as? String,
                                   statusUpdatedAt: updated)
    }

    /// The live sessions in `directory`: files whose process still runs.
    public static func read(_ directory: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/sessions"),
                            isAlive: (Int32) -> Bool = { kill($0, 0) == 0 }) -> [ClaudeRegistryEntry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { (try? Data(contentsOf: $0)).flatMap(parse) }
            .filter { isAlive($0.pid) }
            .sorted { $0.pid < $1.pid }
    }
}
