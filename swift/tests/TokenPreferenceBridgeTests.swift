import XCTest

@testable import Spectra

/// Editing the tracked-token list, across the binding.
///
/// Every rule here used to live in `AppState`: the symbol's shape, a
/// seven-arm switch that judged a contract by hosting chain and assumed EVM in
/// its `default`, the duplicate check, a `min(max(decimals, 0), 30)` clamp and
/// a re-sort — with core storing whatever list came back. These run against a
/// service with no endpoints and no database, because none of the rules needs
/// either.
final class TokenPreferenceBridgeTests: XCTestCase {
    private func service() throws -> WalletService { try WalletService.newTyped(endpoints: []) }

    private func rejection(_ transition: StateTransition) -> String? {
        transition.events.first(where: { $0.kind == "tokenPreferenceRejected" })?.subjectId
    }

    private func add(
        _ service: WalletService, chain: String, symbol: String, contract: String,
        decimals: UInt32 = 18
    ) async throws -> StateTransition {
        try await service.applyStateCommand(
            command: .addCustomToken(
                chainName: chain, symbol: symbol, name: "A Token", contract: contract,
                coingeckoId: "", decimals: decimals))
    }

    func testACustomTokenIsJudgedByTheChainThatWouldHostItAcrossAsyncBinding() async throws {
        let service = try service()
        let solanaMint = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
        let evmContract = "0x742d35cc6634c0532925a3b844bc454e4438f44e"

        let wrongFamily = try await add(
            service, chain: "Base", symbol: "USDC", contract: solanaMint, decimals: 6)
        XCTAssertEqual(rejection(wrongFamily), "invalidContract")

        let accepted = try await add(
            service, chain: "Base", symbol: "  moon ", contract: evmContract)
        XCTAssertNil(rejection(accepted))
        let stored = try XCTUnwrap(
            accepted.state.tokenPreferences.first(where: { !$0.isBuiltIn }))
        XCTAssertEqual(stored.token.symbol, "MOON", "the symbol is trimmed and upper-cased")
        XCTAssertFalse(stored.isBuiltIn)

        // The same contract in another case is the same token.
        let duplicate = try await add(
            service, chain: "Base", symbol: "SUN", contract: evmContract.uppercased())
        XCTAssertEqual(rejection(duplicate), "duplicateToken")
    }

    /// A precision no token has is refused rather than clamped into range. A
    /// clamp stores a number the user did not type and reads every later
    /// balance at that scale.
    func testAnImpossiblePrecisionIsRefusedRatherThanClamped() async throws {
        let service = try service()
        let transition = try await add(
            service, chain: "Base", symbol: "DEEP",
            contract: "0x1111111111111111111111111111111111111111", decimals: 31)
        XCTAssertEqual(rejection(transition), "tooManyDecimals")
        XCTAssertFalse(
            transition.state.tokenPreferences.contains { $0.token.symbol == "DEEP" },
            "a refused token must not be stored at any precision")
    }

    /// The catalog's rows are not the user's to remove.
    func testABuiltInTokenIsNotRemovable() async throws {
        let service = try service()
        let seeded = try await service.applyStateCommand(command: .mergeBuiltInTokens)
        let builtIn = try XCTUnwrap(seeded.state.tokenPreferences.first(where: { $0.isBuiltIn }))
        let transition = try await service.applyStateCommand(
            command: .removeCustomToken(
                chainName: builtIn.token.chain, contract: builtIn.token.contract))
        XCTAssertEqual(rejection(transition), "builtInToken")
        XCTAssertEqual(
            transition.state.tokenPreferences.count, seeded.state.tokenPreferences.count)
    }

    /// Untracking is a flag, not a deletion — so the row survives to carry the
    /// choice through the next catalog merge.
    func testUntrackingKeepsTheRow() async throws {
        let service = try service()
        let seeded = try await service.applyStateCommand(command: .mergeBuiltInTokens)
        let target = try XCTUnwrap(seeded.state.tokenPreferences.first(where: { $0.isEnabled }))
        let key = CoreTokenPreferenceKey(
            chainName: target.token.chain, contract: target.token.contract)

        let off = try await service.applyStateCommand(
            command: .setTokenPreferencesEnabled(tokens: [key], isEnabled: false))
        XCTAssertEqual(
            off.state.tokenPreferences.count, seeded.state.tokenPreferences.count,
            "untracking is not deleting")
        XCTAssertFalse(
            try XCTUnwrap(
                off.state.tokenPreferences.first {
                    $0.token.chain == target.token.chain
                        && $0.token.contract == target.token.contract
                }
            ).isEnabled)
    }
}
