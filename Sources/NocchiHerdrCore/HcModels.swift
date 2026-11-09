import Foundation

/// A program's own status report (OSC 7501 `state=…:app=…`). Words are the program's own.
public struct HcStatus: Decodable, Hashable, Sendable {
    /// "idle", "working", "done", "blocked" or "error".
    public var state: String
    /// The program: "claude-code", "codex", "pi", …
    public var app: String?
    /// For `blocked`: "permission", "question" or "auth".
    public var kind: String?
    public var msg: String?

    public init(state: String, app: String? = nil, kind: String? = nil, msg: String? = nil) {
        self.state = state
        self.app = app
        self.kind = kind
        self.msg = msg
    }
}

/// A terminal as herdr-core reports it (`events.subscribe`, `created` events). Only the fields
/// nocchi uses.
public struct HcTerminal: Decodable, Hashable, Sendable {
    /// `t7`: this terminal forever on this core.
    public var address: String
    /// "live" or "finished".
    public var state: String
    /// The launch folder.
    public var cwd: String?
    public var title: String?
    /// Goes up each time the status leaves `working`.
    public var turn: Int
    /// Free-form; herdr-app writes `herdr.seen` (the turn the person has seen), `herdr.space`,
    /// `herdr.tab` and `where`.
    public var labels: [String: String]
    /// Null when the program never reported, or after it exited back to the shell.
    public var status: HcStatus?
    /// The folder the foreground program is in now.
    public var foregroundCwd: String?
    /// The foreground program's process (Claude's session registry is keyed by it).
    public var foregroundPID: Int32?

    public init(
        address: String, state: String = "live", cwd: String? = nil, title: String? = nil, turn: Int = 0,
        labels: [String: String] = [:], status: HcStatus? = nil, foregroundCwd: String? = nil, foregroundPID: Int32? = nil
    ) {
        self.address = address
        self.state = state
        self.cwd = cwd
        self.title = title
        self.turn = turn
        self.labels = labels
        self.status = status
        self.foregroundCwd = foregroundCwd
        self.foregroundPID = foregroundPID
    }

    private enum CodingKeys: String, CodingKey { case address, state, cwd, title, turn, labels, status, foreground }
    private struct Foreground: Decodable { var cwd: String?; var pid: Int32? }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        address = try c.decode(String.self, forKey: .address)
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? "live"
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        turn = try c.decodeIfPresent(Int.self, forKey: .turn) ?? 0
        labels = try c.decodeIfPresent([String: String].self, forKey: .labels) ?? [:]
        status = try c.decodeIfPresent(HcStatus.self, forKey: .status)
        let foreground = try c.decodeIfPresent(Foreground.self, forKey: .foreground)
        foregroundCwd = foreground?.cwd
        foregroundPID = foreground?.pid
    }

    /// The turn herdr-app last showed the person, if it says.
    var seenTurn: Int? { labels["herdr.seen"].flatMap { Int($0) } }
}

/// `events.subscribe` → `result`: every terminal, and the sequence number events continue from.
public struct HcSubscription: Decodable, Sendable {
    public var seq: Int
    public var terminals: [HcTerminal]
}

/// A notification on a subscription connection.
public enum HcEvent: Hashable, Sendable {
    case created(HcTerminal)
    case status(terminal: String, HcStatus?)
    case turn(terminal: String, turn: Int)
    case title(terminal: String, String)
    /// The labels that changed (merged into the known ones).
    case labels(terminal: String, [String: String])
    case foreground(terminal: String, cwd: String?, pid: Int32?)
    /// The program died (it may be restarted as a shell).
    case lost(terminal: String)
    case finished(terminal: String)
    case removed(terminal: String)
    /// A shared document changed (herdr-app's layout is `herdr-app`).
    case doc(name: String)
    case heartbeat
    /// The subscriber fell behind: only a fresh snapshot can tell what changed.
    case missed

    /// Decodes one notification line. Returns `nil` for replies, unknown events and malformed
    /// lines.
    public static func decode(_ line: Data) -> HcEvent? {
        struct Envelope: Decodable { var method: String; var params: Params? }
        struct Params: Decodable { var type: String?; var terminal: String?; var data: Payload? }
        struct Payload: Decodable {
            var status: HcStatus?
            var turn: Int?
            var title: String?
            var labels: [String: String]?
            var cwd: String?
            var pid: Int32?
            var name: String?
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: line) else { return nil }
        switch envelope.method {
        case "heartbeat": return .heartbeat
        case "missed": return .missed
        case "event": break
        default: return nil
        }
        guard let params = envelope.params, let type = params.type else { return nil }
        let data = params.data
        if type == "doc" { return data?.name.map { .doc(name: $0) } }
        if type == "created" {
            struct Created: Decodable { var params: Params; struct Params: Decodable { var data: HcTerminal } }
            return (try? JSONDecoder().decode(Created.self, from: line)).map { .created($0.params.data) }
        }
        guard let terminal = params.terminal else { return nil }
        switch type {
        case "status": return .status(terminal: terminal, data?.status)
        case "turn": return data?.turn.map { .turn(terminal: terminal, turn: $0) }
        case "title": return .title(terminal: terminal, data?.title ?? "")
        case "labels": return .labels(terminal: terminal, data?.labels ?? [:])
        case "foreground": return .foreground(terminal: terminal, cwd: data?.cwd, pid: data?.pid)
        case "lost": return .lost(terminal: terminal)
        case "finished": return .finished(terminal: terminal)
        case "removed": return .removed(terminal: terminal)
        default: return nil
        }
    }
}

/// herdr-app's layout document (`doc.get herdr-app`): which space and tab show each terminal.
/// Only names are used.
public struct HerdrAppLayout: Decodable, Hashable, Sendable {
    public var spaces: [Space]

    public struct Space: Decodable, Hashable, Sendable {
        public var id: String
        public var name: String?
        public var folder: String?
        public var tabs: [Tab]

        public init(id: String, name: String?, folder: String? = nil, tabs: [Tab]) {
            self.id = id
            self.name = name
            self.folder = folder
            self.tabs = tabs
        }

        private enum CodingKeys: String, CodingKey { case id, name, folder, tabs }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decodeIfPresent(String.self, forKey: .name)
            folder = try c.decodeIfPresent(String.self, forKey: .folder)
            tabs = try c.decodeIfPresent([Tab].self, forKey: .tabs) ?? []
        }
    }

    public struct Tab: Decodable, Hashable, Sendable {
        public var id: String
        public var name: String?
        /// The terminals shown in the tab's panes.
        public var terminals: [String]

        public init(id: String, name: String?, terminals: [String]) {
            self.id = id
            self.name = name
            self.terminals = terminals
        }

        private enum CodingKeys: String, CodingKey { case id, name, root }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decodeIfPresent(String.self, forKey: .name)
            terminals = try c.decodeIfPresent(Node.self, forKey: .root)?.terminals ?? []
        }
    }

    /// A split tree: blocks show a terminal, rows and columns hold children.
    private struct Node: Decodable {
        var content: Content?
        var children: [Node]?
        struct Content: Decodable { var terminal: String? }
        var terminals: [String] { [content?.terminal].compactMap { $0 } + (children ?? []).flatMap(\.terminals) }
    }

    public init(spaces: [Space]) { self.spaces = spaces }

    private enum CodingKeys: String, CodingKey { case spaces }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        spaces = try c.decodeIfPresent([Space].self, forKey: .spaces) ?? []
    }

    /// Each terminal's name: its space's, else its tab's unless that's only a number ("1").
    public var names: [String: String] {
        var names: [String: String] = [:]
        for space in spaces {
            for tab in space.tabs {
                let name = [space.name, tab.name].lazy.compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                    .first { !$0.isEmpty && !$0.allSatisfy(\.isNumber) }
                for terminal in tab.terminals { names[terminal] = name }
            }
        }
        return names
    }
}
