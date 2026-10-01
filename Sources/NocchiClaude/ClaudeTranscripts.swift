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

    /// Phrases for the tool calls appended to `session`'s transcript since the last call, oldest
    /// first. The first call returns only the latest one, so a busy agent shows its current step
    /// right away without replaying its history.
    public func newPhrases(session: String) -> [String] {
        guard let tail = tails[session] else {
            guard let found = locate(session) else { return [] }
            return firstRead(session, found)
        }
        guard let (phrases, offset) = Self.read(tail.url, from: tail.offset) else { return [] }
        tails[session]?.offset = offset
        return phrases
    }

    /// Looks back from the end, widening the window until a tool call turns up: a transcript can
    /// end in a few huge lines (pasted images, long tool output).
    private func firstRead(_ session: String, _ found: Tail) -> [String] {
        let size = (try? FileManager.default.attributesOfItem(atPath: found.url.path)[.size] as? UInt64) ?? 0
        tails[session] = Tail(url: found.url, offset: size)
        var window = Self.initialWindow
        while true {
            let start = size > window ? size - window : 0
            guard let (phrases, offset) = Self.read(found.url, from: start, skippingFirstLine: start > 0) else { return [] }
            tails[session]?.offset = offset
            if let latest = phrases.last { return [latest] }
            if start == 0 || window >= Self.maxWindow { return [] }
            window *= 4
        }
    }

    static let maxWindow: UInt64 = 8 * 1024 * 1024

    /// Phrases in the complete lines from `start`, and the offset after the last complete line.
    private static func read(_ url: URL, from start: UInt64, skippingFirstLine: Bool = false) -> ([String], UInt64)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size < start ? 0 : start  // rewritten
        guard size > start, (try? handle.seek(toOffset: start)) != nil,
              let data = try? handle.read(upToCount: Int(size - start)),
              let lastNewline = data.lastIndex(of: 0x0A) else { return ([], start) }
        // Only complete lines; the rest is read next time.
        let offset = start + UInt64(data.distance(from: data.startIndex, to: lastNewline) + 1)
        var lines = data[data.startIndex...lastNewline].split(separator: 0x0A, omittingEmptySubsequences: true)
        // Starting mid-file, the first line is probably cut.
        if skippingFirstLine, !lines.isEmpty { lines.removeFirst() }
        return (lines.compactMap { ClaudeActivity.phrase(forLine: Data($0)) }, offset)
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

/// Feeds what Claude Code agents are doing into the store as `.step` events, whichever adapter
/// reports them (they only need a Claude session ID). Busy agents are checked every second;
/// others once, when they first appear.
@MainActor
public final class ClaudeActivityFeed {
    private let store: AgentStore
    private let transcripts: ClaudeTranscripts
    private var task: Task<Void, Never>?
    private var seen: Set<String> = []

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
            guard Self.isBusy(entry.info.status) || !seen.contains(session) else { continue }
            seen.insert(session)
            for phrase in await transcripts.newPhrases(session: session) {
                store.apply(.step(entry.ref, phrase), from: entry.ref.adapter)
            }
        }
        seen.formIntersection(sessions)
        await transcripts.keep(only: sessions)
    }

    static func isBusy(_ status: AgentStatus) -> Bool {
        switch status {
        case .working, .thinking, .starting, .blocked: true
        case .idle, .done, .error: false
        }
    }
}
