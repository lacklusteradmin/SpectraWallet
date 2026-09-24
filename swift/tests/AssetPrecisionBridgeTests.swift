import XCTest
@testable import Spectra

@MainActor
final class AssetPrecisionBridgeTests: IsolatedAppStateTestCase {
    func testPrecisionSnapshotUpdatesAndRejectsStaleResults() async throws {
        let store = makeState()
        XCTAssertEqual(store.amounts.formattedAssetAmountValue("1", deploymentId: "ethereum:native"), "—")
        let contract = "0x1111111111111111111111111111111111111111"
        _ = try await bridge.applyStateCommand(.addCustomToken(
            chainId: "ethereum", symbol: "CUSTOM", name: "Custom", contract: contract,
            coingeckoId: "", coinpaprikaId: "", decimals: 6))
        let old = try await bridge.portfolioSnapshot()
        let id = "ethereum:erc-20:\(contract)"
        store.applyPortfolioSnapshot(old)
        XCTAssertEqual(store.assetPrecision?.byDeploymentId[id], 6)
        XCTAssertEqual(store.assetPrecision?.byDeploymentId["bitcoin:native"], 8)
        _ = try await bridge.applyStateCommand(.setCustomTokenDecimals(chainId: "ethereum", contract: contract, decimals: 4))
        let current = try await bridge.portfolioSnapshot()
        store.applyPortfolioSnapshot(current)
        store.applyPortfolioSnapshot(old)
        XCTAssertEqual(store.assetPrecision?.byDeploymentId[id], 4)
        // The render path uses the coherent core snapshot.
        // Cut, never rounded up.
        XCTAssertTrue(store.amounts.formattedAssetAmountValue("0.123456", deploymentId: id).hasSuffix("1234"))
        _ = try await bridge.applyStateCommand(.removeCustomToken(chainId: "ethereum", contract: contract))
        store.applyPortfolioSnapshot(try await bridge.portfolioSnapshot())
        XCTAssertNil(store.assetPrecision?.byDeploymentId[id])
        XCTAssertEqual(store.assetPrecision?.unknownDecimals, 18)
    }
}
