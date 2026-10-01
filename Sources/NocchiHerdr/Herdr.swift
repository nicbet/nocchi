import Foundation
import NocchiCore

public enum Herdr {
    /// The Herdr API protocol this adapter was written against (Herdr 0.9).
    public static let supportedProtocol = 22

    /// Where Herdr's API socket lives: an explicit path, else a named session's socket, else the
    /// default session's. A GUI app doesn't inherit `HERDR_SOCKET_PATH`, so this never reads it.
    public static func socketPath(override: String? = nil, session: String? = nil, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        if let override, !override.isEmpty { return (override as NSString).expandingTildeInPath }
        let herdr = home.appending(path: ".config/herdr")
        if let session, !session.isEmpty {
            return herdr.appending(path: "sessions/\(session)/herdr.sock").path
        }
        return herdr.appending(path: "herdr.sock").path
    }
}

/// Everything that can go wrong talking to Herdr.
public enum HerdrError: Error, Equatable, CustomStringConvertible {
    /// No socket, nobody listening, or the connection dropped.
    case unavailable(String)
    /// Herdr answered with an error.
    case api(code: String, message: String)
    /// Herdr didn't answer in time.
    case timeout
    /// Herdr answered with something we couldn't decode.
    case badResponse(String)

    public var description: String {
        switch self {
        case .unavailable(let reason): "Herdr unavailable: \(reason)"
        case .api(let code, let message): "Herdr error \(code): \(message)"
        case .timeout: "Herdr didn't answer in time"
        case .badResponse(let detail): "Unexpected Herdr response: \(detail)"
        }
    }

    var code: String? { if case .api(let code, _) = self { code } else { nil } }
}
