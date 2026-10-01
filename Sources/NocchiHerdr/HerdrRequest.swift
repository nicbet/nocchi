import Foundation

/// A JSON value for request parameters.
public enum JSONValue: Hashable, Sendable, Codable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    case string(String), int(Int), bool(Bool), array([JSONValue]), object([String: JSONValue])

    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) { self = .object(Dictionary(uniqueKeysWithValues: elements)) }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }
}

/// One Herdr API request. Built only through the factories below, so the schema drift test can
/// check every request nocchi sends against `herdr api schema --json`.
public struct HerdrRequest: Hashable, Sendable {
    public let method: String
    public let params: [String: JSONValue]

    /// The NDJSON line for this request.
    func line(id: String) -> Data {
        struct Wire: Encodable { let id: String; let method: String; let params: [String: JSONValue] }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var data = (try? encoder.encode(Wire(id: id, method: method, params: params))) ?? Data()
        data.append(0x0A)
        return data
    }

    public static let ping = HerdrRequest(method: "ping", params: [:])
    public static let snapshot = HerdrRequest(method: "session.snapshot", params: [:])

    /// Status changes must be subscribed per pane (no wildcard); the rest are global.
    public static func subscribe(agentPanes: some Sequence<String>) -> HerdrRequest {
        var subscriptions: [JSONValue] = agentPanes.sorted().map { ["type": "pane.agent_status_changed", "pane_id": .string($0)] }
        for type in globalEvents { subscriptions.append(["type": .string(type)]) }
        return HerdrRequest(method: "events.subscribe", params: ["subscriptions": .array(subscriptions)])
    }

    static let globalEvents = [
        "pane.created", "pane.updated", "pane.closed", "pane.exited", "pane.agent_detected", "pane.focused",
        "tab.renamed",
    ]

    public static func focus(pane: String) -> HerdrRequest {
        HerdrRequest(method: "agent.focus", params: ["target": .string(pane)])
    }

    public static func prompt(pane: String, text: String) -> HerdrRequest {
        HerdrRequest(method: "agent.prompt", params: ["target": .string(pane), "text": .string(text)])
    }

    public static func createWorkspace(cwd: String, label: String) -> HerdrRequest {
        HerdrRequest(method: "workspace.create", params: ["cwd": .string(cwd), "label": .string(label), "focus": false])
    }

    public static func startAgent(name: String, kind: String, pane: String, timeoutMs: Int) -> HerdrRequest {
        HerdrRequest(method: "agent.start", params: [
            "name": .string(name), "kind": .string(kind), "pane_id": .string(pane), "timeout_ms": .int(timeoutMs),
        ])
    }

    public static func closePane(_ pane: String) -> HerdrRequest {
        HerdrRequest(method: "pane.close", params: ["pane_id": .string(pane)])
    }

    /// One of each request nocchi sends, for the schema drift test.
    public static var all: [HerdrRequest] {
        [
            ping, snapshot, subscribe(agentPanes: ["w1:p1"]), focus(pane: "w1:p1"), prompt(pane: "w1:p1", text: "hi"),
            createWorkspace(cwd: "/tmp", label: "tmp"), startAgent(name: "tmp", kind: "claude", pane: "w1:p1", timeoutMs: 30_000),
            closePane("w1:p1"),
        ]
    }
}
