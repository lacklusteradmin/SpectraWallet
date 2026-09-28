import XCTest
import SwiftUI
@testable import Spectra

@MainActor
final class SendStagesViewTests: IsolatedAppStateTestCase {

    func testSignedStageRendersInspectablePayloadAndExplicitDestinations() async throws {
        let state = makeState()
        state.sendFlow.session.endpoints = ["https://ethereum.example/rpc"]
        let artifact = SendArtifact(id: "render-fixture", revision: 1, stage: .signed,
            walletId: "fixture", chainId: "ethereum-sepolia",
            sender: "0x1111111111111111111111111111111111111111",
            recipient: "0x2222222222222222222222222222222222222222",
            amount: "1.000000000000000001", asset: "ETH", createdAt: 0, reviewDigest: "reviewed-content",
            review: SendArtifactReview(warnings: [.newAddress], recipientWarnings: [], requiresSelfSendConfirmation: true),
            preparedDetails: "Nonce: 7\nMaximum gas: 25200", signingPayloadHex: "02",
            signedPayload: "0x02…", transactionHash: "0x1234", attempts: [], selectedEndpoints: [])
        state.sendFlow.session.artifact = artifact
        XCTAssertTrue(state.pendingHighRiskSendReasons[0].contains("1.000000000000000001"))
        XCTAssertEqual(state.pendingHighRiskSendReasons.count, 3)
        let view = ScrollView {
            SendStagesView(store: state, artifact: artifact).padding()
        }.frame(width: 393, height: 852).background(Color(.systemBackground))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        try await Task.sleep(for: .milliseconds(300))
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let pixels = try XCTUnwrap(image.cgImage?.dataProvider?.data) as Data
        XCTAssertGreaterThan(Set(pixels).count, 16, "The render must contain content, not an empty canvas")
        let attachment = XCTAttachment(image: image)
        attachment.name = "Signed transaction awaiting broadcast"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(state.sendFlow.selectedEndpoints.isEmpty, "Rendering must not select destinations or submit")
    }
}
