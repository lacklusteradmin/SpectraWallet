import Foundation

// Thin shorthand over the Rust `buildJsonObject` UniFFI export.
// Every chain-specific send-payload JSON assembles through here so escaping and
// field-ordering live in one Rust implementation rather than N Swift interpolations.

enum SendField: Sendable {
    case str(String, String)
    case uint(String, UInt64)
    case int(String, Int64)
    case double(String, Double)
    case bool(String, Bool)
    case raw(String, String)

    nonisolated var toJsonField: JsonField {
        switch self {
        case .str(let k, let v):    return JsonField(name: k, value: .str(value: v))
        case .uint(let k, let v):   return JsonField(name: k, value: .uInt(value: v))
        case .int(let k, let v):    return JsonField(name: k, value: .int(value: v))
        case .double(let k, let v): return JsonField(name: k, value: .float(value: v))
        case .bool(let k, let v):   return JsonField(name: k, value: .bool(value: v))
        case .raw(let k, let v):    return JsonField(name: k, value: .raw(value: v))
        }
    }
}

nonisolated func sendPayload(_ fields: SendField...) -> String {
    buildJsonObject(fields: fields.map(\.toJsonField))
}
