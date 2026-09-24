import XCTest
@testable import Spectra

@MainActor
final class AssetPrecisionBridgeTests: IsolatedAppStateTestCase {
    func testPrecisionSnapshotUpdatesAndRejectsStaleResults() async throws {
        let store = makeState()
        XCTAssertEqual(store.amounts.formattedAssetAmountValue("1", deploymentId: "ethereum:native"), "—")
        let contract = "0x1111111111111111111111111111111111111111"
        _ = try await bridge.ready().applyStateCommand(command: .addCustomToken(
            chainId: "ethereum", symbol: "CUSTOM", name: "Custom", contract: contract,
            coingeckoId: "", coinpaprikaId: "", decimals: 6))
        let old = try await bridge.ready().portfolioSnapshot()
        let id = "ethereum:erc-20:\(contract)"
        store.applyPortfolioSnapshot(old)
        XCTAssertEqual(store.assetPrecision?.byDeploymentId[id], 6)
        XCTAssertEqual(store.assetPrecision?.byDeploymentId["bitcoin:native"], 8)
        _ = try await bridge.ready().applyStateCommand(command: .setCustomTokenDecimals(chainId: "ethereum", contract: contract, decimals: 4))
        let current = try await bridge.ready().portfolioSnapshot()
        store.applyPortfolioSnapshot(current)
        store.applyPortfolioSnapshot(old)
        XCTAssertEqual(store.assetPrecision?.byDeploymentId[id], 4)
        // The render path uses the coherent core snapshot.
        // Cut, never rounded up.
        XCTAssertTrue(store.amounts.formattedAssetAmountValue("0.123456", deploymentId: id).hasSuffix("1234"))
        _ = try await bridge.ready().applyStateCommand(command: .removeCustomToken(chainId: "ethereum", contract: contract))
        store.applyPortfolioSnapshot(try await bridge.ready().portfolioSnapshot())
        XCTAssertNil(store.assetPrecision?.byDeploymentId[id])
        XCTAssertEqual(store.assetPrecision?.unknownDecimals, 18)
    }
}
