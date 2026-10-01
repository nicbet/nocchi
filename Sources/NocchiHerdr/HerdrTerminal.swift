import AppKit
import NocchiTerminals

/// The terminal apps hosting Herdr clients, so focusing an agent can also bring its terminal to
/// the front (`agent.focus` only switches panes inside Herdr). Several clients can be attached at
/// once, in different apps.
public enum HerdrTerminal {
    /// Brings the terminal running a Herdr client to the front: the one used last, when several
    /// are attached. Returns false if none was found.
    @discardableResult
    @MainActor
    public static func bringToFront() async -> Bool {
        guard let app = TerminalApps.preferred(await hostApps()) else { return false }
        return await TerminalApps.bringToFront(app)
    }

    /// For each Herdr client process, the terminal app it runs in; newest client first, each app
    /// once. Empty when Herdr runs inside tmux or over SSH.
    @MainActor
    static func hostApps() async -> [NSRunningApplication] {
        let table = await ProcessTable.current()
        var hosts: [NSRunningApplication] = []
        for client in table.entries.values.filter(isClient).sorted(by: { $0.pid > $1.pid }) {
            if let app = TerminalApps.host(of: client.pid, in: table),
               !hosts.contains(where: { $0.processIdentifier == app.processIdentifier }) {
                hosts.append(app)
            }
        }
        return hosts
    }

    /// A Herdr client, not its server.
    static func isClient(_ entry: ProcessTable.Entry) -> Bool {
        entry.command == "herdr" && !entry.args.split(separator: " ").contains("server")
    }

    /// Whether a terminal hosting Herdr is frontmost: now, then on every change. Herdr treats a
    /// focused pane as seen; this tells whether anyone could actually see it. With no host found
    /// (Herdr in tmux or over SSH) it reports `true`: plain Herdr behavior.
    @MainActor
    static func frontmostUpdates() -> AsyncStream<Bool> {
        TerminalApps.frontmostUpdates { Set(await hostApps().map(\.processIdentifier)) }
    }
}
