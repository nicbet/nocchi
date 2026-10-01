import Foundation

/// A snapshot of the running processes, enough to walk from an agent (or a Herdr client) up to
/// the terminal app it runs in. `ps` is simpler than reading every process's arguments through
/// `sysctl`, and is only run on demand (a click, an app switch, a new agent).
public struct ProcessTable: Sendable {
    public struct Entry: Hashable, Sendable {
        public var pid: pid_t
        public var ppid: pid_t
        /// Controlling terminal, e.g. "ttys003"; nil for none.
        public var tty: String?
        public var args: String

        /// The executable's file name: "herdr", "claude", "codex", "node".
        public var command: String {
            let first = args.split(separator: " ").first.map(String.init) ?? args
            return (first as NSString).lastPathComponent
        }
    }

    public let entries: [pid_t: Entry]

    public init(entries: [pid_t: Entry]) {
        self.entries = entries
    }

    public static func current() async -> ProcessTable {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let ps = Process()
                ps.executableURL = URL(fileURLWithPath: "/bin/ps")
                ps.arguments = ["-axo", "pid=,ppid=,tty=,args="]
                let pipe = Pipe()
                ps.standardOutput = pipe
                ps.standardError = FileHandle.nullDevice
                guard (try? ps.run()) != nil else { return continuation.resume(returning: ProcessTable(entries: [:])) }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                ps.waitUntilExit()
                continuation.resume(returning: parse(String(decoding: data, as: UTF8.self)))
            }
        }
    }

    /// Parses `ps -axo pid=,ppid=,tty=,args=`.
    public static func parse(_ output: String) -> ProcessTable {
        var entries: [pid_t: Entry] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4, let pid = pid_t(fields[0]), let ppid = pid_t(fields[1]) else { continue }
            let tty = fields[2] == "??" ? nil : String(fields[2])
            entries[pid] = Entry(pid: pid, ppid: ppid, tty: tty, args: fields[3].trimmingCharacters(in: .whitespaces))
        }
        return ProcessTable(entries: entries)
    }

    public subscript(pid: pid_t) -> Entry? { entries[pid] }

    /// `pid`'s parent, grandparent and so on, nearest first (at most 64).
    public func ancestors(of pid: pid_t) -> [Entry] {
        var chain: [Entry] = []
        var current = entries[pid]?.ppid ?? 0
        while current > 1, chain.count < 64, let entry = entries[current] {
            chain.append(entry)
            current = entry.ppid
        }
        return chain
    }
}
