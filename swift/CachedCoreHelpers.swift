import Foundation

/// Swift-side memoization wrappers for Rust-core pure-function helpers.
///
/// Every helper in here is a thin wrapper over a UniFFI function that's
/// deterministic in its inputs (no side effects, no dependency on AppState
/// mutable state). These are exactly the kind of small predicate / lookup
/// helpers Spectra keeps in Rust for cross-platform parity, but which got
/// called inside SwiftUI `body` scopes — multiplying the UniFFI per-call
/// cost by the render frequency.
///
/// Pattern:
/// - `static` pure data → `@MainActor` cache dict, cleared never (or only
///   when the underlying Rust inputs change, which for these helpers is
///   "never at runtime" since they're driven by compile-time tables).
/// - User-typed or unbounded-input helpers → bounded cache with a simple
///   drop-all eviction when the size cap is hit.
///
/// For new FFI helpers added later: if the Rust call is a pure function,
/// add the wrapper here. Don't call the raw UniFFI symbol from a view
/// body directly.
@MainActor
enum CachedCoreHelpers {
    // ── Unbounded caches for fixed-domain helpers ──────────────────────
    private static var dashboardAssetGroupingKeys: [String: String] = [:]
    private static var nativeAssetDisplaySettingsKeys: [String: String] = [:]
    private static var defaultAssetDisplayDecimalsByChainResult: [String: UInt32]?
    private static var stablecoinFallbackPriceUsdBySymbol: [String: Double] = [:]
    private static var evmChainContextTags: [String: String] = [:]
    private static var seedDerivationChainRaws: [String: String?] = [:]
    private static var evmSeedDerivationChainNames: [String: String?] = [:]
    private static var receiveAddressResolvers: [String: ReceiveAddressResolverKind] = [:]

    // ── Bounded cache for user-input helpers ───────────────────────────
    private static var privateKeyHexIsLikelyCache: [String: Bool] = [:]
    private static let privateKeyCacheCap = 128

    // ── formatting.* ───────────────────────────────────────────────────
    static func dashboardAssetGroupingKey(chainIdentity: String, coinGeckoId: String, symbol: String) -> String {
        let cacheKey = "\(chainIdentity)|\(coinGeckoId)|\(symbol)"
        if let cached = dashboardAssetGroupingKeys[cacheKey] { return cached }
        let value = formattingDashboardAssetGroupingKey(chainIdentity: chainIdentity, coinGeckoId: coinGeckoId, symbol: symbol)
        dashboardAssetGroupingKeys[cacheKey] = value
        return value
    }
    static func nativeAssetDisplaySettingsKey(chainName: String) -> String {
        if let cached = nativeAssetDisplaySettingsKeys[chainName] { return cached }
        let value = formattingNativeAssetDisplaySettingsKey(chainName: chainName)
        nativeAssetDisplaySettingsKeys[chainName] = value
        return value
    }
    static func defaultAssetDisplayDecimalsByChain(defaultValue: UInt32) -> [String: UInt32] {
        // `defaultValue` is a caller-side fallback baked into the request;
        // callers use a single value app-wide, so cache the whole map.
        if let cached = defaultAssetDisplayDecimalsByChainResult { return cached }
        let value = formattingDefaultAssetDisplayDecimalsByChain(defaultValue: defaultValue)
        defaultAssetDisplayDecimalsByChainResult = value
        return value
    }
    static func stablecoinFallbackPriceUsd(symbol: String) -> Double {
        if let cached = stablecoinFallbackPriceUsdBySymbol[symbol] { return cached }
        let value = formattingStablecoinFallbackPriceUsd(symbol: symbol)
        stablecoinFallbackPriceUsdBySymbol[symbol] = value
        return value
    }

    // ── core.* predicates + enum mappers ───────────────────────────────
    static func evmChainContextTag(chainName: String, ethereumNetworkMode: String) -> String {
        let key = "\(chainName)|\(ethereumNetworkMode)"
        if let cached = evmChainContextTags[key] { return cached }
        let value = coreEvmChainContextTag(chainName: chainName, ethereumNetworkMode: ethereumNetworkMode)
        evmChainContextTags[key] = value
        return value
    }
    static func seedDerivationChainRaw(chainName: String) -> String? {
        if let cached = seedDerivationChainRaws[chainName] { return cached }
        let value = coreSeedDerivationChainRaw(chainName: chainName)
        seedDerivationChainRaws[chainName] = value
        return value
    }
    static func evmSeedDerivationChainName(chainName: String) -> String? {
        if let cached = evmSeedDerivationChainNames[chainName] { return cached }
        let value = coreEvmSeedDerivationChainName(chainName: chainName)
        evmSeedDerivationChainNames[chainName] = value
        return value
    }
    static func receiveAddressResolver(symbol: String, chainName: String, isEvmChain: Bool) -> ReceiveAddressResolverKind {
        let key = "\(symbol)|\(chainName)|\(isEvmChain ? "1" : "0")"
        if let cached = receiveAddressResolvers[key] { return cached }
        let value = corePlanReceiveAddressResolver(symbol: symbol, chainName: chainName, isEvmChain: isEvmChain)
        receiveAddressResolvers[key] = value
        return value
    }
    static func privateKeyHexIsLikely(rawValue: String) -> Bool {
        if let cached = privateKeyHexIsLikelyCache[rawValue] { return cached }
        let value = corePrivateKeyHexIsLikely(rawValue: rawValue)
        if privateKeyHexIsLikelyCache.count > privateKeyCacheCap {
            privateKeyHexIsLikelyCache.removeAll(keepingCapacity: true)
        }
        privateKeyHexIsLikelyCache[rawValue] = value
        return value
    }
}
