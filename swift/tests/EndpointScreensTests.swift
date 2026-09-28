import XCTest
import SwiftUI
@testable import Spectra

@MainActor
final class EndpointScreensTests: IsolatedAppStateTestCase {

    func testEndpointScreensRenderInARealWindow() async throws {
        let state = makeState()
        let directory = try await bridge.ready().endpointDirectory()
        let views: [(String, AnyView)] = [
            ("Endpoints", AnyView(NavigationStack { EndpointCatalogSettingsView(store: state) })),
            ("Add endpoint", AnyView(NavigationStack { AddCustomEndpointView(store: state, directory: directory) })),
            ("Explorers", AnyView(NavigationStack { ExplorerSettingsView() }))
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
