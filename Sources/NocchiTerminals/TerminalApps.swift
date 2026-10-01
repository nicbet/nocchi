import AppKit

/// The terminal app an agent runs in: the first regular macOS app above its process. Works for
/// any terminal (Ghostty, iTerm, Terminal, WezTerm, kitty, an IDE's terminal); none is named.
@MainActor
public enum TerminalApps {
    /// The host the user was last in, preferred when several could be brought forward.
    public static var lastActive: pid_t?

    /// The first regular app up `pid`'s parent chain; nil inside tmux or over SSH, where the chain
    /// doesn't reach a local app.
    ///
    /// Some terminals run their shells under a separate daemon whose parent is `launchd`, so the
    /// chain never reaches the app (iTerm: `login … /Applications/iTerm.app/…/ShellLauncher` under
    /// `iTermServer`). Then an app bundle named in the chain's command lines identifies it.
    public static func host(of pid: pid_t, in table: ProcessTable) -> NSRunningApplication? {
        let chain = [table[pid]].compactMap({ $0 }) + table.ancestors(of: pid)
        for entry in chain {
            if let app = NSRunningApplication(processIdentifier: entry.pid), app.activationPolicy == .regular { return app }
        }
        let bundles = ProcessTable.appBundles(in: chain)
        guard !bundles.isEmpty else { return nil }
        return NSWorkspace.shared.runningApplications.first { app in
            app.activationPolicy == .regular && app.bundleURL.map { bundles.contains($0.standardizedFileURL.path) } == true
        }
    }

    /// Brings `app` to the front.
    ///
    /// Since macOS 14 a background app can't activate another one: `activate()` and
    /// `NSWorkspace.openApplication` both quietly leave the frontmost app in place. Handing the
    /// request to `/usr/bin/open` works and needs no Automation permission.
    @discardableResult
    public static func bringToFront(_ app: NSRunningApplication) async -> Bool {
        let arguments: [String]
        if let bundleID = app.bundleIdentifier {
            arguments = ["-b", bundleID]
        } else if let url = app.bundleURL {
            arguments = ["-a", url.path]
        } else {
            return app.activate()
        }
        return await withCheckedContinuation { continuation in
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = arguments
            open.terminationHandler = { continuation.resume(returning: $0.terminationStatus == 0) }
            do { try open.run() } catch { continuation.resume(returning: false) }
        }
    }

    /// Of `apps`, the one the user was last in, else the first.
    public static func preferred(_ apps: [NSRunningApplication]) -> NSRunningApplication? {
        apps.first { $0.processIdentifier == lastActive } ?? apps.first
    }

    /// Whether one of the hosts `hosts` finds is the frontmost app: now, then on every change.
    /// `hosts` is asked again when an unknown app comes to the front (a terminal window may have
    /// attached or quit since). No hosts at all reports `true`: nothing to be behind.
    public static func frontmostUpdates(hosts: @escaping @MainActor () async -> Set<pid_t>) -> AsyncStream<Bool> {
        let (stream, continuation) = AsyncStream.makeStream(of: Bool.self, bufferingPolicy: .bufferingNewest(1))
        let watcher = FrontmostWatcher(continuation, hosts: hosts)
        continuation.onTermination = { _ in Task { @MainActor in watcher.stop() } }
        Task { await watcher.start() }
        return stream
    }
}

@MainActor
private final class FrontmostWatcher {
    let continuation: AsyncStream<Bool>.Continuation
    let findHosts: @MainActor () async -> Set<pid_t>
    var hosts: Set<pid_t> = []
    var observer: NSObjectProtocol?
    var last: Bool?

    init(_ continuation: AsyncStream<Bool>.Continuation, hosts: @escaping @MainActor () async -> Set<pid_t>) {
        self.continuation = continuation
        findHosts = hosts
    }

    func start() async {
        hosts = await findHosts()
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
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if let front, hosts.contains(front) {
            report()
        } else {
            Task {
                hosts = await findHosts()
                report()
            }
        }
    }

    private func report() {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if let front, hosts.contains(front) { TerminalApps.lastActive = front }
        let frontmost = hosts.isEmpty || front.map(hosts.contains) == true
        guard frontmost != last else { return }
        last = frontmost
        continuation.yield(frontmost)
    }
}

extension TerminalApps {
    /// The frontmost app's pid: now, then on every change.
    public static func frontmostAppUpdates() -> AsyncStream<pid_t> {
        let (stream, continuation) = AsyncStream.makeStream(of: pid_t.self, bufferingPolicy: .bufferingNewest(4))
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier { continuation.yield(pid) }
        let observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if let pid = app?.processIdentifier { continuation.yield(pid) }
        }
        let token = UncheckedBox(observer)
        continuation.onTermination = { _ in NSWorkspace.shared.notificationCenter.removeObserver(token.value) }
        return stream
    }
}

/// Carries a value the compiler can't prove `Sendable` (a notification observer token) across.
private struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
