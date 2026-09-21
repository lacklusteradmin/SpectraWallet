import Foundation

/// Process-lifetime copies of core's compile-time tables.
/// Fetch and index each table once for per-row view lookups. Do not cache
/// secret inputs or helpers that are already cheap local lookups.
@MainActor
enum CoreReferenceTables {
    private static var assetWikiEntries: [AssetWikiEntry]?
    private static var assetWikiByTokenId: [String: AssetWikiEntry]?
    private static var chainWikiEntries: [ChainWikiEntry]?
    private static var chainWikiById: [String: ChainWikiEntry]?
    private static var standardPhraseLengths: [SeedPhraseLength]?

    // ── wiki.* ────────────────────────────────────────────────────────
    //
    // Both wikis are compile-time tables, so one call each for the life of the
    // process. The by-key forms exist because the callers are lookups, not
    // iterations: a places card resolves one chain per row, and a detail view
    // resolves one coin. Scanning the list for those meant a full FFI clone
    // and a linear search per row, per render.
    static func assetWiki() -> [AssetWikiEntry] {
        if let cached = assetWikiEntries { return cached }
        let value = listAssetWiki()
        assetWikiEntries = value
        return value
    }
    static func assetWikiEntry(tokenId: String) -> AssetWikiEntry? {
        if assetWikiByTokenId == nil {
            assetWikiByTokenId = Dictionary(
                assetWiki().map { ($0.tokenId, $0) }, uniquingKeysWith: { first, _ in first })
        }
        return assetWikiByTokenId?[tokenId]
    }
    static func chainWiki() -> [ChainWikiEntry] {
        if let cached = chainWikiEntries { return cached }
        let value = listChainWiki()
        chainWikiEntries = value
        return value
    }
    static func chainWikiEntry(id: String) -> ChainWikiEntry? {
        if chainWikiById == nil {
            chainWikiById = Dictionary(
                chainWiki().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        return chainWikiById?[id]
    }

    // BIP-39 lengths and entropy as defined by core, one picker chip per entry.
    static func standardSeedPhraseLengths() -> [SeedPhraseLength] {
        if let cached = standardPhraseLengths { return cached }
        let value = seedPhraseLengths()
        standardPhraseLengths = value
        return value
    }
    /// Whether BIP-39 defines a phrase of this length.
    static func isStandardSeedPhraseLength(_ wordCount: Int) -> Bool {
        standardSeedPhraseLengths().contains { Int($0.wordCount) == wordCount }
    }

}
