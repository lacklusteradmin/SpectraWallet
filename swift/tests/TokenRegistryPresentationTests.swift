import XCTest
import SwiftUI

@testable import Spectra

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
        let seeded = try await bridge.ready().applyStateCommand(command: .mergeBuiltInTokens)
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
}
