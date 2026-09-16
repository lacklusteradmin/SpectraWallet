import Foundation

/// Process-lifetime copies of core's compile-time tables.
///
/// Each of these is a list core parses from a bundled TOML and clones across
/// the boundary whole on every call. The views ask for one row at a time, per
/// render, so the list is fetched once and indexed here.
///
/// That is the only thing that belongs here. This file used to say "add every
/// pure FFI helper", and it grew a cache of registry lookups that were already
/// local dictionary reads, a pass-through that cached nothing, and a bounded
/// cache keyed by the private-key candidates a user typed — up to 128 of them
/// held for the life of the process, to save a string comparison. A call that
/// is cheap, or whose input is a secret, is made where it is needed.
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

    // ── seed phrase lengths ───────────────────────────────────────────
    //
    // The five BIP-39 lengths and the entropy each carries, as core defines
    // them. The picker renders one chip per entry; both the list and the
    // entropy used to be written out here, next to a third copy in the import
    // draft and two more in Rust.
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
