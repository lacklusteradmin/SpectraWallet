import Foundation

/// Utility for decoding the chain-specific JSON blobs returned by WalletServiceBridge
/// balance fetches into Swift numeric types.
enum RustBalanceDecoder {

    // MARK: - Generic field extractors

    /// Extract a UInt64 from a named field in a JSON object string.
    /// The field may be serialized as a JSON number or a decimal string.
    static func uint64Field(_ field: String, from json: String) -> UInt64? {
        guard let obj = parseObject(json) else { return nil }
        if let n = obj[field] as? NSNumber { return n.uint64Value }
        if let s = obj[field] as? String   { return UInt64(s) }
        return nil
    }

    /// Extract an Int64 from a named field in a JSON object string.
    static func int64Field(_ field: String, from json: String) -> Int64? {
        guard let obj = parseObject(json) else { return nil }
        if let n = obj[field] as? NSNumber { return n.int64Value }
        if let s = obj[field] as? String   { return Int64(s) }
        return nil
    }

    /// Extract a field that may be a u128 (serialized as a decimal string or a JSON number)
    /// and return its value as a Double.  Precision loss is acceptable for display use.
    static func uint128StringField(_ field: String, from json: String) -> Double? {
        guard let obj = parseObject(json) else { return nil }
        if let n = obj[field] as? NSNumber { return n.doubleValue }
        if let s = obj[field] as? String   { return Double(s) }
        return nil
    }

    // MARK: - Chain-specific decoders

    /// Parse an EVM native balance JSON and return the coin amount as a Double.
    ///
    /// Rust emits `{ "balance_wei": "<u256-decimal-string>", "balance_display": "<decimal>" … }`.
    /// We prefer `balance_display` (already divided by 1e18 by Rust) when present;
    /// fall back to dividing `balance_wei` by 1e18 ourselves.
    static func evmNativeBalance(from json: String) -> Double? {
        guard let obj = parseObject(json) else { return nil }
        if let s = obj["balance_display"] as? String, let v = Double(s) { return v }
        if let n = obj["balance_wei"] as? NSNumber { return n.doubleValue / 1e18 }
        if let s = obj["balance_wei"] as? String, let wei = Double(s) { return wei / 1e18 }
        return nil
    }

    /// Parse a NEAR balance JSON and return the NEAR amount as a Double.
    ///
    /// Rust emits `{ "yocto_near": "<u128-string>", "near_display": "<decimal>" … }`.
    /// 1 NEAR = 1 × 10²⁴ yoctoNEAR.
    static func yoctoNearToDouble(from json: String) -> Double? {
        guard let obj = parseObject(json) else { return nil }
        if let s = obj["near_display"] as? String, let v = Double(s) { return v }
        if let s = obj["yocto_near"] as? String, let yocto = Double(s) { return yocto / 1e24 }
        if let n = obj["yocto_near"] as? NSNumber { return n.doubleValue / 1e24 }
        return nil
    }

    // MARK: - Private

    private static func parseObject(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
