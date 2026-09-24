import XCTest
import SwiftUI
@testable import Spectra

@MainActor
final class EndpointDirectoryBridgeTests: IsolatedAppStateTestCase {
    func testTypedEndpointsCrossTheBindingAndKeepTheirSourceAndNetwork() async throws {
        let before = try await bridge.ready().endpointDirectory()
        let transition = try await bridge.ready().applyStateCommand(command: .setAppSetting(update: .addCustomEndpoint(
            capabilities: ["balance"],             chainId: "solana", api: "solana-json-rpc", endpoint: " https://custom.example/rpc/ ")))
        XCTAssertFalse(transition.events.contains(.appSettingRejected))
        let after = try await bridge.ready().endpointDirectory()
        XCTAssertEqual(after.filter(\.isBuiltIn).count, before.filter(\.isBuiltIn).count)
        let custom = try XCTUnwrap(after.first { !$0.isBuiltIn })
        XCTAssertEqual(custom.record.chainId, "solana")
        XCTAssertEqual(custom.apiName, "solana-json-rpc")
        XCTAssertEqual(custom.record.endpoint, "https://custom.example/rpc")
        XCTAssertEqual(custom.record.capabilities, ["balance"])
        XCTAssertNil(custom.record.probeUrl)
        let noCapabilities = try await bridge.ready().applyStateCommand(command: .setAppSetting(update: .addCustomEndpoint(
            capabilities: [], chainId: "solana", api: "solana-json-rpc", endpoint: "https://empty.example")))
        XCTAssertTrue(noCapabilities.events.contains(.appSettingRejected))
        let rejected = try await bridge.ready().applyStateCommand(command: .setAppSetting(update: .addCustomEndpoint(
            capabilities: ["balance"],             chainId: "solana", api: "esplora", endpoint: "https://wrong.example")))
        XCTAssertTrue(rejected.events.contains(.appSettingRejected))
    }

    func testEndpointScreensRenderInARealWindow() async throws {
        let state = makeState()
        let directory = try await bridge.ready().endpointDirectory()
        let views: [(String, AnyView)] = [
            ("Endpoints", AnyView(NavigationStack { EndpointCatalogSettingsView(store: state) })),
            ("Add endpoint", AnyView(NavigationStack { AddCustomEndpointView(store: state, directory: directory) }))
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
            try await Task.sleep(for: .milliseconds(400))
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
