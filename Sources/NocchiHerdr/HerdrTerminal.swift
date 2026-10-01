import AppKit

/// Finds the terminal apps hosting Herdr clients (any terminal: whichever regular app sits above a
/// client process), so focusing an agent can also bring its terminal to the front. `agent.focus`
/// only switches panes inside Herdr. Several clients can be attached at once, in different apps.
public enum HerdrTerminal {
    /// The host the user was last in, preferred when several are attached.
    @MainActor static var lastActiveHost: pid_t?

    /// Brings the terminal running a Herdr client to the front: the one used last, when several
    /// are attached. Returns false if none was found.
    ///
    /// Since macOS 14 a background app can't activate another one: `activate()` and
    /// `NSWorkspace.openApplication` both quietly leave the frontmost app in place. Handing the
    /// request to `/usr/bin/open` works and needs no Automation permission.
    @discardableResult
    @MainActor
    public static func bringToFront() async -> Bool {
        let hosts = await hostApps()
        guard let app = hosts.first(where: { $0.processIdentifier == lastActiveHost }) ?? hosts.first else { return false }
        let arguments: [String]
        if let bundleID = app.bundleIdentifier {
            arguments = ["-b", bundleID]
        } else if let url = app.bundleURL {
            arguments = ["-a", url.path]
        } else {
            return app.activate()
        }
        return await withCheckedContinuation { continuation in
            let open = Foundation.Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = arguments
            open.terminationHandler = { continuation.resume(returning: $0.terminationStatus == 0) }
            do { try open.run() } catch { continuation.resume(returning: false) }
        }
    }

    /// For each Herdr client process, the first regular app up its parent chain; newest client
    /// first, each app once. Empty when Herdr runs inside tmux or over SSH.
    @MainActor
    static func hostApps() async -> [NSRunningApplication] {
        let table = await processTable()
        let clients = table.values.filter { $0.isHerdr && !$0.isServer }.sorted { $0.pid > $1.pid }
        var hosts: [NSRunningApplication] = []
        for client in clients {
            var pid = client.ppid
            var hops = 0
            while pid > 1, hops < 32 {
                if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular {
                    if !hosts.contains(where: { $0.processIdentifier == pid }) { hosts.append(app) }
                    break
                }
                guard let parent = table[pid] else { break }
                pid = parent.ppid
                hops += 1
            }
        }
        return hosts
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

/// Whether a terminal app hosting Herdr is the frontmost app: now, then on every change.
/// Herdr treats a focused pane as seen; this tells whether anyone could actually see it.
/// When no host can be found (Herdr in tmux or over SSH, say), it reports `true`: plain Herdr
/// behavior.
@MainActor
enum TerminalPresence {
    static func updates() -> AsyncStream<Bool> {
        let (stream, continuation) = AsyncStream.makeStream(of: Bool.self, bufferingPolicy: .bufferingNewest(1))
        let watcher = Watcher(continuation)
        continuation.onTermination = { _ in Task { @MainActor in watcher.stop() } }
        Task { await watcher.start() }
        return stream
    }

    @MainActor
    private final class Watcher {
        let continuation: AsyncStream<Bool>.Continuation
        var hosts: Set<pid_t> = []
        var observer: NSObjectProtocol?
        var last: Bool?

        init(_ continuation: AsyncStream<Bool>.Continuation) {
            self.continuation = continuation
        }

        func start() async {
            await refreshHosts()
            report()
            observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.activated() }
            }
        }

        func stop() {
            observer.map(NSWorkspace.shared.notificationCenter.removeObserver)
            observer = nil
        }

        private func activated() {
            // Clients come and go (a new terminal window attaches, one quits): look again when
            // the frontmost app isn't a known host.
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if let front, hosts.contains(front) {
                report()
            } else {
                Task {
                    await refreshHosts()
                    report()
                }
            }
        }

        private func refreshHosts() async {
            hosts = Set(await HerdrTerminal.hostApps().map(\.processIdentifier))
        }

        private func report() {
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if let front, hosts.contains(front) { HerdrTerminal.lastActiveHost = front }
            let frontmost = hosts.isEmpty || front.map(hosts.contains) == true
            guard frontmost != last else { return }
            last = frontmost
            continuation.yield(frontmost)
        }
    }
}
