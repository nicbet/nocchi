import Foundation
import NocchiHerdr

/// One herdr-core API request. Built only through the factories below, so the schema drift test
/// can check every request nocchi sends against `hc schema`.
public struct HcRequest: Hashable, Sendable {
    public let method: String
    public let params: [String: JSONValue]

    /// The JSON-RPC line for this request.
    func line(id: String) -> Data {
        struct Wire: Encodable { let jsonrpc = "2.0"; let id: String; let method: String; let params: [String: JSONValue] }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var data = (try? encoder.encode(Wire(id: id, method: method, params: params))) ?? Data()
        data.append(0x0A)
        return data
    }

    public static let hello = HcRequest(method: "hello", params: [:])

    /// Every terminal, then every change to them.
    public static let subscribe = HcRequest(method: "events.subscribe", params: [:])

    /// Pastes `text` into the terminal and presses Enter.
    public static func send(terminal: String, text: String) -> HcRequest {
        HcRequest(method: "terminal.send", params: ["terminal": .string(terminal), "text": .string(text)])
    }

    /// herdr-app keeps its layout (spaces, tabs, which terminal is where) in this document.
    public static let appLayout = HcRequest(method: "doc.get", params: ["name": "herdr-app"])

    /// One of each request nocchi sends, for the schema drift test.
    public static var all: [HcRequest] {
        [hello, subscribe, send(terminal: "t1", text: "hi"), appLayout]
    }
}
