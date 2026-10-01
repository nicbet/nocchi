import AppKit

/// Finds the terminal app hosting a Herdr client, so focusing an agent can also bring its
/// terminal to the front. `agent.focus` only switches panes inside Herdr.
public enum HerdrTerminal {
    /// Brings the terminal running a Herdr client to the front. Returns false if none was found.
    @discardableResult
    @MainActor
    public static func bringToFront() async -> Bool {
        guard let app = await hostApp() else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        if let url = app.bundleURL {
            // Opening a running app activates it, which works from a background app where
            // `activate()` may be refused under cooperative activation.
            return (try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)) != nil
        }
        return app.activate()
    }

    /// The first regular app up the parent chain of a Herdr client process.
    @MainActor
    static func hostApp() async -> NSRunningApplication? {
        let table = await processTable()
        let clients = table.values.filter { $0.isHerdr && !$0.isServer }.sorted { $0.pid > $1.pid }
        for client in clients {
            var pid = client.ppid
            var hops = 0
            while pid > 1, hops < 32 {
                if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular { return app }
                guard let parent = table[pid] else { break }
                pid = parent.ppid
                hops += 1
            }
        }
        return nil
    }

    struct Process: Hashable {
        var pid: pid_t
        var ppid: pid_t
        var args: String

        var isHerdr: Bool { args.split(separator: " ").first.map { $0.hasSuffix("herdr") } ?? false }
        var isServer: Bool { args.split(separator: " ").contains("server") }
    }

    /// `ps` is simpler than reading every process's arguments through `sysctl`, and runs once per click.
    static func processTable() async -> [pid_t: Process] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let ps = Foundation.Process()
                ps.executableURL = URL(fileURLWithPath: "/bin/ps")
                ps.arguments = ["-axo", "pid=,ppid=,args="]
                let pipe = Pipe()
                ps.standardOutput = pipe
                ps.standardError = FileHandle.nullDevice
                guard (try? ps.run()) != nil else { return continuation.resume(returning: [:]) }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                ps.waitUntilExit()
                continuation.resume(returning: parse(String(decoding: data, as: UTF8.self)))
            }
        }
    }

    static func parse(_ output: String) -> [pid_t: Process] {
        var table: [pid_t: Process] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count == 3, let pid = pid_t(fields[0]), let ppid = pid_t(fields[1]) else { continue }
            table[pid] = Process(pid: pid, ppid: ppid, args: String(fields[2]))
        }
        return table
    }
}
