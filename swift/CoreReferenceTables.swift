import Foundation

/// Process-lifetime copies of core's compile-time tables, each fetched and
/// indexed once on first use. Do not cache secret inputs or helpers that are
/// already cheap local lookups.
///
/// The by-key forms exist because the callers are lookups, not iterations: a
/// places card resolves one chain per row, and a detail view resolves one
/// coin. Scanning the list for those meant a full FFI clone and a linear
/// search per row, per render.
enum CoreReferenceTables {
    static let assetWiki: [AssetWikiEntry] = listAssetWiki()
    private static let assetWikiByTokenId = Dictionary(
        assetWiki.map { ($0.tokenId, $0) }, uniquingKeysWith: { first, _ in first })
    static let chainWiki: [ChainWikiEntry] = listChainWiki()
    private static let chainWikiById = Dictionary(
        chainWiki.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    /// BIP-39 lengths and entropy as defined by core, one picker chip per entry.
    static let standardSeedPhraseLengths: [SeedPhraseLength] = seedPhraseLengths()
    /// Every BIP-39 wordlist, English first, as core names and codes them.
    static let seedPhraseWordlists: [SeedPhraseLanguage] = seedPhraseLanguages()
    /// What staking means on each chain that stakes, in catalog order.
    static let stakingChains: [StakingChainEntry] = listStakingChains()
    /// The bounds core holds edits to, for the controls that set them.
    static let bounds: InputBounds = inputBounds()
    private static let stakingByChain = Dictionary(uniqueKeysWithValues: stakingChains.map { ($0.chain, $0) })

    static func assetWikiEntry(tokenId: String) -> AssetWikiEntry? { assetWikiByTokenId[tokenId] }
    static func chainWikiEntry(id: String) -> ChainWikiEntry? { chainWikiById[id] }
    static func stakingEntry(for chain: Chain) -> StakingChainEntry? { stakingByChain[chain] }
}
