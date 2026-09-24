import XCTest
import SwiftUI

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
    private func service() throws -> WalletService { try WalletService(endpoints: []) }

    private func rejection(_ transition: StateTransition) -> TokenPreferenceRejection? {
        for case .tokenPreferenceRejected(let reason) in transition.events { return reason }
        return nil
    }

    private func add(
        _ service: WalletService, chainId: String, symbol: String, contract: String,
        decimals: UInt32 = 18
    ) async throws -> StateTransition {
        try await service.applyStateCommand(
            command: .addCustomToken(
                chainId: chainId, symbol: symbol, name: "A Token", contract: contract,
                coingeckoId: "", coinpaprikaId: "", decimals: decimals))
    }

    func testACustomTokenIsJudgedByTheChainThatWouldHostItAcrossAsyncBinding() async throws {
        let service = try service()
        let solanaMint = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
        let evmContract = "0x742d35cc6634c0532925a3b844bc454e4438f44e"

        let wrongFamily = try await add(
            service, chainId: "base", symbol: "USDC", contract: solanaMint, decimals: 6)
        XCTAssertEqual(rejection(wrongFamily), .invalidContract)

        let accepted = try await add(
            service, chainId: "base", symbol: "  moon ", contract: evmContract)
        XCTAssertNil(rejection(accepted))
        let stored = try XCTUnwrap(
            accepted.state.tokenPreferences.first(where: { !$0.isBuiltIn }))
        XCTAssertEqual(stored.token.symbol, "MOON", "the symbol is trimmed and upper-cased")
        XCTAssertEqual(stored.token.chainId, "base")
        XCTAssertEqual(stored.token.deploymentId, "base:erc-20:\(evmContract)")
        XCTAssertFalse(stored.isBuiltIn)

        // The same contract in another case is the same token.
        let duplicate = try await add(
            service, chainId: "base", symbol: "SUN", contract: evmContract.uppercased())
        XCTAssertEqual(rejection(duplicate), .duplicateToken)
    }

    /// A precision no token has is refused rather than clamped into range. A
    /// clamp stores a number the user did not type and reads every later
    /// balance at that scale.
    func testAnImpossiblePrecisionIsRefusedRatherThanClamped() async throws {
        let service = try service()
        let transition = try await add(
            service, chainId: "base", symbol: "DEEP",
            contract: "0x1111111111111111111111111111111111111111", decimals: 31)
        XCTAssertEqual(rejection(transition), .tooManyDecimals)
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
                chainId: builtIn.token.chainId, contract: builtIn.token.contract))
        XCTAssertEqual(rejection(transition), .builtInToken)
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
            chainId: target.token.chainId, contract: target.token.contract)

        let off = try await service.applyStateCommand(
            command: .setTokenPreferencesEnabled(tokens: [key], isEnabled: false))
        XCTAssertEqual(
            off.state.tokenPreferences.count, seeded.state.tokenPreferences.count,
            "untracking is not deleting")
        XCTAssertFalse(
            try XCTUnwrap(
                off.state.tokenPreferences.first {
                    $0.token.chainId == target.token.chainId
                        && $0.token.contract == target.token.contract
                }
            ).isEnabled)
    }
}

@MainActor
final class TokenRegistryPresentationTests: IsolatedAppStateTestCase {
    func testCustomEditorPersistsBothPriceSourcesAndKeepsIdentity() async throws {
        let state = makeState()
        let identifier = "0x1111111111111111111111111111111111111111"
        let added = await state.addCustomTokenPreference(chain: .ethereum, symbol: "DEMO", name: "Demo",
            contractAddress: identifier, coinpaprikaId: "demo-token", decimals: 6)
        XCTAssertNil(added)
        let entry = try XCTUnwrap(state.tokenPreferences.first { !$0.isBuiltIn })
        XCTAssertEqual(entry.token.coinpaprikaId, "demo-token")
        XCTAssertEqual(entry.token.coingeckoId, "")
        let edited = await state.addCustomTokenPreference(chain: .ethereum, symbol: "NEW", name: "New Demo",
            contractAddress: identifier, coingeckoId: "demo", coinpaprikaId: "demo-new", decimals: 8, editing: entry)
        XCTAssertNil(edited)
        let current = try XCTUnwrap(state.tokenPreferences.first { $0.id == entry.id })
        XCTAssertEqual(current.token.tokenId, entry.token.tokenId)
        XCTAssertEqual(current.token.name, "New Demo")
        XCTAssertEqual(current.token.coinpaprikaId, "demo-new")
        XCTAssertEqual(current.token.coingeckoId, "demo")
        let reopened = WalletServiceBridge(databasePath: directory.appendingPathComponent("state.sqlite").path,
            service: try WalletService(endpoints: []))
        let persisted = try await reopened.openState()
        XCTAssertEqual(persisted.tokenPreferences.first { $0.id == entry.id }?.token, current.token)
    }

    func testTokenManagementScreensRenderInARealWindow() async throws {
        let state = makeState()
        let seeded = try await bridge.applyStateCommand(.mergeBuiltInTokens)
        state.applyCoreState(seeded.state)
        let entry = try XCTUnwrap(state.tokenPreferences.first { $0.token.symbol == "USDC" })
        let views: [(String, AnyView)] = [
            ("Known tokens", AnyView(NavigationStack { TokenRegistrySettingsView(store: state) })),
            ("Token detail", AnyView(NavigationStack { TokenRegistryDetailView(store: state, groupKey: entry.token.tokenId) })),
            ("Custom token form", AnyView(NavigationStack { AddCustomTokenView(store: state) }))
        ]
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        for (name, view) in views {
            window.rootViewController = UIHostingController(rootView: view)
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(300))
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let pixels = try XCTUnwrap(image.cgImage?.dataProvider?.data) as Data
            XCTAssertGreaterThan(Set(pixels).count, 16)
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testOneDeploymentToggleChangesEveryNetworkThroughBinding() async throws {
        let seeded = try await bridge.applyStateCommand(.mergeBuiltInTokens)
        let entry = try XCTUnwrap(seeded.state.tokenPreferences.first { $0.token.symbol == "USDC" })
        let transition = try await bridge.applyStateCommand(.setTokenPreferencesEnabled(tokens: [
            CoreTokenPreferenceKey(chainId: entry.token.chainId, contract: entry.token.contract)
        ], isEnabled: false))
        let deployments = transition.state.tokenPreferences.filter { $0.token.tokenId == entry.token.tokenId }
        XCTAssertGreaterThan(deployments.count, 2)
        XCTAssertTrue(deployments.allSatisfy { !$0.isEnabled })
    }
}
