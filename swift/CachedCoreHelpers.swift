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
    private static var allChainsResult: [ChainEntry]?
    private static var allTokensResult: [TokenEntry]?
    private static var supportedPrivateKeyChainNamesResult: [String]?
    private static var dashboardAssetGroupingKeys: [String: String] = [:]
    private static var nativeAssetDisplaySettingsKeys: [String: String] = [:]
    private static var defaultAssetDisplayDecimalsByChainResult: [String: UInt32]?
    private static var stablecoinFallbackPriceUsdBySymbol: [String: Double] = [:]
    private static var evmChainContextTags: [String: String] = [:]
    private static var seedDerivationChainRaws: [String: String?] = [:]
    private static var evmSeedDerivationChainNames: [String: String?] = [:]
    private static var receiveAddressResolvers: [String: ReceiveAddressResolverKind] = [:]
    private static var resolvedChainIds: [String: String] = [:]

    // ── Bounded cache for user-input helpers ───────────────────────────
    private static var privateKeyHexIsLikelyCache: [String: Bool] = [:]
    private static let privateKeyCacheCap = 128

    private static func cached<K: Hashable, V>(in cache: inout [K: V], key: K, _ compute: () -> V) -> V {
        if let hit = cache[key] { return hit }
        let v = compute(); cache[key] = v; return v
    }
    private static func cachedBounded<K: Hashable, V>(in cache: inout [K: V], key: K, cap: Int, _ compute: () -> V) -> V {
        if let hit = cache[key] { return hit }
        if cache.count >= cap { cache.removeAll(keepingCapacity: true) }
        let v = compute(); cache[key] = v; return v
    }

    // ── chains.* / tokens.* ───────────────────────────────────────────
    static func allChains() -> [ChainEntry] {
        if let cached = allChainsResult { return cached }
        let value = listAllChains()
        allChainsResult = value
        return value
    }
    static func allTokens() -> [TokenEntry] {
        if let cached = allTokensResult { return cached }
        let value = listTokens(chainId: "")
        allTokensResult = value
        return value
    }
    static func supportedPrivateKeyChainNames() -> [String] {
        if let cached = supportedPrivateKeyChainNamesResult { return cached }
        let value = coreSupportedPrivateKeyChainNames()
        supportedPrivateKeyChainNamesResult = value
        return value
    }
    static func resolveChainId(input: String) -> String {
        cached(in: &resolvedChainIds, key: input) {
            coreResolveChainId(input: input)
        }
    }

    // ── formatting.* ───────────────────────────────────────────────────
    static func dashboardAssetGroupingKey(chainIdentity: String, coinGeckoId: String, symbol: String) -> String {
        cached(in: &dashboardAssetGroupingKeys, key: "\(chainIdentity)|\(coinGeckoId)|\(symbol)") {
            formattingDashboardAssetGroupingKey(chainIdentity: chainIdentity, coinGeckoId: coinGeckoId, symbol: symbol)
        }
    }
    static func nativeAssetDisplaySettingsKey(chainName: String) -> String {
        cached(in: &nativeAssetDisplaySettingsKeys, key: chainName) {
            formattingNativeAssetDisplaySettingsKey(chainName: chainName)
        }
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
        cached(in: &stablecoinFallbackPriceUsdBySymbol, key: symbol) {
            formattingStablecoinFallbackPriceUsd(symbol: symbol)
        }
    }

    // ── core.* predicates + enum mappers ───────────────────────────────
    static func evmChainContextTag(chainName: String, ethereumNetworkMode: String) -> String {
        cached(in: &evmChainContextTags, key: "\(chainName)|\(ethereumNetworkMode)") {
            coreEvmChainContextTag(chainName: chainName, ethereumNetworkMode: ethereumNetworkMode)
        }
    }
    static func seedDerivationChainRaw(chainName: String) -> String? {
        cached(in: &seedDerivationChainRaws, key: chainName) {
            coreSeedDerivationChainRaw(chainName: chainName)
        }
    }
    static func evmSeedDerivationChainName(chainName: String) -> String? {
        cached(in: &evmSeedDerivationChainNames, key: chainName) {
            coreEvmSeedDerivationChainName(chainName: chainName)
        }
    }
    static func receiveAddressResolver(symbol: String, chainName: String, isEvmChain: Bool) -> ReceiveAddressResolverKind {
        cached(in: &receiveAddressResolvers, key: "\(symbol)|\(chainName)|\(isEvmChain ? "1" : "0")") {
            corePlanReceiveAddressResolver(symbol: symbol, chainName: chainName, isEvmChain: isEvmChain)
        }
    }
    static func privateKeyHexIsLikely(rawValue: String) -> Bool {
        cachedBounded(in: &privateKeyHexIsLikelyCache, key: rawValue, cap: privateKeyCacheCap) {
            corePrivateKeyHexIsLikely(rawValue: rawValue)
        }
    }
    nonisolated static func chainDerivationPath(chainName: String) -> String {
        let p = listAllChains().first(where: { $0.name == chainName })?.derivationPath ?? ""
        return p.hasPrefix("m/") ? p : ""
    }
}
