import Foundation
@testable import NocchiHerdr

/// Checks requests against the installed Herdr's `herdr api schema --json`, so a Herdr upgrade
/// that renames a method or parameter fails a test instead of failing silently in the app.
struct HerdrSchema {
    private let root: [String: Any]

    /// `nil` when Herdr isn't installed.
    static func installed() throws -> HerdrSchema? {
        guard let herdr = IsolatedHerdr.findHerdr() else { return nil }
        let process = Process()
        process.executableURL = herdr
        process.arguments = ["api", "schema", "--json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return HerdrSchema(root: root)
    }

    var protocolVersion: Int? { root["protocol"] as? Int }

    /// Problems with `request`, empty if it matches the schema.
    func validate(_ request: HerdrRequest) -> [String] {
        let data = request.line(id: "check")
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return ["\(request.method): not JSON"] }
        let schema: [String: Any] = ["$ref": "#/schemas/request"]
        return validate(json, against: schema, at: request.method)
    }

    /// The subset of JSON Schema Herdr's schema uses. Unlike JSON Schema's default, a property
    /// the schema doesn't list is an error: that's exactly how a renamed parameter shows up.
    private func validate(_ value: Any, against schema: [String: Any], at path: String) -> [String] {
        if let ref = schema["$ref"] as? String {
            guard let resolved = resolve(ref) else { return ["\(path): unresolved \(ref)"] }
            return validate(value, against: resolved, at: path)
        }
        var problems: [String] = []
        for key in ["oneOf", "anyOf"] {
            guard let options = schema[key] as? [[String: Any]] else { continue }
            let results = options.map { validate(value, against: $0, at: path) }
            if !results.contains(where: \.isEmpty) {
                problems.append("\(path): matches none of \(key) (closest: \(results.min { $0.count < $1.count } ?? []))")
            }
        }
        if let constant = schema["const"], !equal(constant, value) { problems.append("\(path): expected \(constant), got \(value)") }
        if let options = schema["enum"] as? [Any], !options.contains(where: { equal($0, value) }) {
            problems.append("\(path): \(value) not in \(options)")
        }
        if let type = schema["type"] {
            let types = (type as? [String]) ?? [type as? String].compactMap { $0 }
            if !types.contains(where: { matches(value, $0) }) { problems.append("\(path): \(value) isn't \(types)") }
        }
        if let object = value as? [String: Any] {
            let properties = schema["properties"] as? [String: [String: Any]]
            for key in schema["required"] as? [String] ?? [] where object[key] == nil {
                problems.append("\(path): missing \(key)")
            }
            if let properties {
                for (key, child) in object {
                    if let property = properties[key] {
                        problems += validate(child, against: property, at: "\(path)/\(key)")
                    } else if key != "id" || path.contains("/") {
                        problems.append("\(path): unknown property \(key)")
                    }
                }
            }
        }
        if let array = value as? [Any], let items = schema["items"] as? [String: Any] {
            for (index, item) in array.enumerated() { problems += validate(item, against: items, at: "\(path)[\(index)]") }
        }
        return problems
    }

    private func resolve(_ ref: String) -> [String: Any]? {
        var node: Any = root
        for part in ref.dropFirst(2).split(separator: "/") {
            guard let dict = node as? [String: Any], let next = dict[String(part)] else { return nil }
            node = next
        }
        guard var schema = node as? [String: Any] else { return nil }
        // The top-level request schema lists `id` and the method variants side by side.
        if ref == "#/schemas/request" {
            var properties = schema["properties"] as? [String: Any] ?? [:]
            properties["method"] = [:] as [String: Any]
            properties["params"] = [:] as [String: Any]
            schema["properties"] = properties
        }
        return schema
    }

    private func matches(_ value: Any, _ type: String) -> Bool {
        switch type {
        case "string": value is String
        case "integer": (value as? NSNumber).map { !isBool($0) && $0.doubleValue == $0.doubleValue.rounded() } ?? false
        case "boolean": (value as? NSNumber).map(isBool) ?? false
        case "object": value is [String: Any]
        case "array": value is [Any]
        case "null": value is NSNull
        default: true
        }
    }

    private func isBool(_ number: NSNumber) -> Bool { CFGetTypeID(number) == CFBooleanGetTypeID() }

    private func equal(_ a: Any, _ b: Any) -> Bool { (a as? NSObject)?.isEqual(b) ?? false }
}
