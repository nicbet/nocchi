import Foundation
import NocchiCore

/// Follows Claude Code session transcripts and reports the tool calls appended since last time.
/// Reads only new bytes; a session's file is found once, by its ID, under `~/.claude/projects`.
public actor ClaudeTranscripts {
    private let root: URL
    private var tails: [String: Tail] = [:]
    /// Sessions without a transcript yet, and when we last looked.
    private var missing: [String: Date] = [:]

    private struct Tail {
        var url: URL
        var offset: UInt64
    }

    /// The first read of a transcript looks at this much of its end for the latest step.
    static let initialWindow: UInt64 = 256 * 1024

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/projects")) {
        self.root = root
    }

    /// What was appended to a transcript since the last look.
    public struct Activity: Equatable, Sendable {
        /// Tool calls, oldest first.
        public var phrases: [String] = []
        /// The opening of the latest message to the user, if a new one arrived.
        public var message: String?
    }

    /// Activity appended to `session`'s transcript since the last call. The first call returns
    /// only the last two steps (current and previous) and the latest message, so an agent shows
    /// where it is right away without replaying its history.
    public func newActivity(session: String) -> Activity {
        guard let tail = tails[session] else {
            guard let found = locate(session) else { return Activity() }
            return firstRead(session, found)
        }
        guard let (activity, offset) = Self.read(tail.url, from: tail.offset) else { return Activity() }
        tails[session]?.offset = offset
        return activity
    }

    /// Just the tool-call phrases (see `newActivity`).
    public func newPhrases(session: String) -> [String] {
        newActivity(session: session).phrases
    }

    /// Looks back from the end, widening the window until a tool call turns up: a transcript can
    /// end in a few huge lines (pasted images, long tool output).
    private func firstRead(_ session: String, _ found: Tail) -> Activity {
        let size = (try? FileManager.default.attributesOfItem(atPath: found.url.path)[.size] as? UInt64) ?? 0
        tails[session] = Tail(url: found.url, offset: size)
        var window = Self.initialWindow
        while true {
            let start = size > window ? size - window : 0
            guard let (activity, offset) = Self.read(found.url, from: start, skippingFirstLine: start > 0) else { return Activity() }
            tails[session]?.offset = offset
            if !activity.phrases.isEmpty {
                return Activity(phrases: Array(activity.phrases.suffix(2)), message: activity.message)
            }
            if start == 0 || window >= Self.maxWindow { return Activity(message: activity.message) }
            window *= 4
        }
    }

    static let maxWindow: UInt64 = 8 * 1024 * 1024

    /// Activity in the complete lines from `start`, and the offset after the last complete line.
    private static func read(_ url: URL, from start: UInt64, skippingFirstLine: Bool = false) -> (Activity, UInt64)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size < start ? 0 : start  // rewritten
        guard size > start, (try? handle.seek(toOffset: start)) != nil,
              let data = try? handle.read(upToCount: Int(size - start)),
              let lastNewline = data.lastIndex(of: 0x0A) else { return (Activity(), start) }
        // Only complete lines; the rest is read next time.
        let offset = start + UInt64(data.distance(from: data.startIndex, to: lastNewline) + 1)
        var lines = data[data.startIndex...lastNewline].split(separator: 0x0A, omittingEmptySubsequences: true)
        // Starting mid-file, the first line is probably cut.
        if skippingFirstLine, !lines.isEmpty { lines.removeFirst() }
        var activity = Activity()
        for line in lines {
            let data = Data(line)
            if let phrase = ClaudeActivity.phrase(forLine: data) { activity.phrases.append(phrase) }
            if let message = ClaudeActivity.message(forLine: data) { activity.message = message }
        }
        return (activity, offset)
    }

    /// Stops following sessions that are gone.
    public func keep(only sessions: Set<String>) {
        tails = tails.filter { sessions.contains($0.key) }
        missing = missing.filter { sessions.contains($0.key) }
    }

    private func locate(_ session: String) -> Tail? {
        if let lastLook = missing[session], Date().timeIntervalSince(lastLook) < 10 { return nil }
        let name = "\(session).jsonl"
        let projects = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for project in projects {
            let url = project.appending(path: name)
            if FileManager.default.fileExists(atPath: url.path) {
                missing[session] = nil
                return Tail(url: url, offset: 0)
            }
        }
        missing[session] = Date()
        return nil
    }
}

/// Feeds what Claude Code agents are doing into the store, whichever adapter reports them (they
/// only need a Claude session ID): tool calls as `.step` events, their latest words to the user as
/// `.message`. Every agent is checked each second; only bytes added since are read, and a turn's
/// final message often lands just as the agent goes idle.
@MainActor
public final class ClaudeActivityFeed {
    private let store: AgentStore
    private let transcripts: ClaudeTranscripts
    private var task: Task<Void, Never>?

    public init(store: AgentStore, transcripts: ClaudeTranscripts = ClaudeTranscripts()) {
        self.store = store
        self.transcripts = transcripts
    }

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    private func poll() async {
        let agents = store.state.agents.values.filter { $0.info.kind == .claude && $0.info.sessionID != nil }
        var sessions: Set<String> = []
        for entry in agents {
            guard let session = entry.info.sessionID else { continue }
            sessions.insert(session)
            let activity = await transcripts.newActivity(session: session)
            for phrase in activity.phrases {
                store.apply(.step(entry.ref, phrase), from: entry.ref.adapter)
            }
            if let message = activity.message {
                store.apply(.message(entry.ref, message), from: entry.ref.adapter)
            }
        }
        await transcripts.keep(only: sessions)
    }
}
