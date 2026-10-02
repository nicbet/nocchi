import Foundation

/// Runs a command in a new window or tab of the user's terminal.
///
/// Writes a one-shot `.command` script and hands it to `/usr/bin/open`, so it opens in whichever
/// app handles `.command` files (Terminal, or iTerm when it's set as the default). Needs no
/// Automation permission, and the shell is the user's login shell with their `PATH`.
public enum TerminalLauncher {
    /// Opens a terminal running `arguments` in `folder`. The script deletes itself as it starts.
    public static func run(_ arguments: [String], in folder: URL) async throws {
        let script = FileManager.default.temporaryDirectory
            .appending(path: "nocchi-\(UUID().uuidString.prefix(8)).command")
        try Self.script(arguments, in: folder).write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let status = await withCheckedContinuation { continuation in
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = [script.path]
            open.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try open.run() } catch { continuation.resume(returning: -1) }
        }
        if status != 0 {
            try? FileManager.default.removeItem(at: script)
            throw LaunchError(message: "Couldn't open a terminal")
        }
    }

    public struct LaunchError: Error, CustomStringConvertible {
        public let message: String
        public var description: String { message }
    }

    static func script(_ arguments: [String], in folder: URL) -> String {
        """
        #!/bin/sh
        rm -f "$0"
        cd \(quote(folder.path)) || exit 1
        clear
        exec \(arguments.map(quote).joined(separator: " "))

        """
    }

    /// Single-quotes `text` for `sh`.
    static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
