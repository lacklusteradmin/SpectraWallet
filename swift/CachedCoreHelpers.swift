import Foundation

/// Process-lifetime copies of core's compile-time tables.
/// Fetch and index each table once for per-row view lookups. Do not cache
/// secret inputs or helpers that are already cheap local lookups.
@MainActor
enum CachedCoreHelpers {
    private static var assetWikiResult: [AssetWikiEntry]?
    private static var assetWikiByTokenID: [String: AssetWikiEntry]?
    private static var chainWikiResult: [ChainWikiEntry]?
    private static var chainWikiByID: [String: ChainWikiEntry]?
    private static var seedPhraseLengthsResult: [SeedPhraseLength]?

    // ── wiki.* ────────────────────────────────────────────────────────
    //
    // Both wikis are compile-time tables, so one call each for the life of the
    // process. The by-key forms exist because the callers are lookups, not
    // iterations: a places card resolves one chain per row, and a detail view
    // resolves one coin. Scanning the list for those meant a full FFI clone
    // and a linear search per row, per render.
    static func assetWiki() -> [AssetWikiEntry] {
        if let cached = assetWikiResult { return cached }
        let value = listAssetWiki()
        assetWikiResult = value
        return value
    }
    static func assetWikiEntry(tokenID: String) -> AssetWikiEntry? {
        if assetWikiByTokenID == nil {
            assetWikiByTokenID = Dictionary(
                assetWiki().map { ($0.tokenId, $0) }, uniquingKeysWith: { first, _ in first })
        }
        return assetWikiByTokenID?[tokenID]
    }
    static func chainWiki() -> [ChainWikiEntry] {
        if let cached = chainWikiResult { return cached }
        let value = listChainWiki()
        chainWikiResult = value
        return value
    }
    static func chainWikiEntry(id: String) -> ChainWikiEntry? {
        if chainWikiByID == nil {
            chainWikiByID = Dictionary(
                chainWiki().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        return chainWikiByID?[id]
    }

    // BIP-39 lengths and entropy as defined by core, one picker chip per entry.
    static func standardSeedPhraseLengths() -> [SeedPhraseLength] {
        if let cached = seedPhraseLengthsResult { return cached }
        let value = seedPhraseLengths()
        seedPhraseLengthsResult = value
        return value
    }
    /// Whether BIP-39 defines a phrase of this length.
    static func isStandardSeedPhraseLength(_ wordCount: Int) -> Bool {
        standardSeedPhraseLengths().contains { Int($0.wordCount) == wordCount }
    }

}
