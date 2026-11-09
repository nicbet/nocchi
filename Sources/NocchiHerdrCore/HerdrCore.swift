import Foundation
import NocchiHerdr

/// The Herdr GUI: two independent programs.
/// - herdr-core (`hc`) runs the terminals and knows each agent's status. JSON-RPC 2.0, one
///   message per line.
/// - herdr-app is the window (spaces, tabs, panes). Its control socket takes one JSON line per
///   connection: `{"ls":{}}`, `{"status":{}}`, `{"do":"<command>","args":{…}}`.
public enum HerdrCore {
    /// The herdr-core API generation this adapter was written against (hc 0.1).
    public static let supportedGeneration = 1

    /// herdr-core's socket for the default session. A GUI app doesn't inherit `HC_SOCKET` or
    /// `XDG_STATE_HOME`, so this never reads them.
    public static func socketPath(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        home.appending(path: ".local/state/herdr-core/default/default.sock").path
    }

    /// herdr-app's control socket.
    public static func appSocketPath(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        home.appending(path: ".config/herdr-app/herdr-app.sock").path
    }

    /// herdr-app's bundle identifier, to bring its window to the front.
    public static let appBundleID = "dev.herdr.app"

    /// The `kind` of an API error (`not_found`, `blocked`, …), if `error` is one.
    static func kind(_ error: Error) -> String? {
        if case HerdrError.api(let code, _) = error { code } else { nil }
    }
}
