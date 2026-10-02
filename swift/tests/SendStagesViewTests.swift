import Foundation
import Testing
import SwiftUI
import UIKit
@testable import Spectra

@MainActor
@Suite(.isolatedAppState)
struct SendStagesViewTests: IsolatedAppStateSuite {

    @Test func signedStageRendersInspectablePayloadAndExplicitDestinations() async throws {
        let state = makeState()
        state.sendFlow.session.endpoints = ["https://ethereum.example/rpc"]
        let artifact = SendArtifact(id: "render-fixture", revision: 1, stage: .signed,
            walletId: "fixture", chainId: Chain.ethereumSepolia,
            sender: "0x1111111111111111111111111111111111111111",
            recipient: "0x2222222222222222222222222222222222222222",
            amount: "1.000000000000000001", asset: "ETH", symbol: "ETH", createdAt: 0, reviewDigest: "reviewed-content",
            review: SendArtifactReview(warnings: [.newAddress], recipientWarnings: [], requiresSelfSendConfirmation: true),
            preparedDetails: "Nonce: 7\nMaximum gas: 25200", signingPayloadHex: "02",
            signedPayload: "0x02…", transactionHash: "0x1234", attempts: [], selectedEndpoints: [])
        state.sendFlow.session.artifact = artifact
        #expect(state.pendingHighRiskSendReasons[0].contains("1.000000000000000001"))
        #expect(state.pendingHighRiskSendReasons.count == 3)
        let view = ScrollView {
            SendStagesView(store: state, artifact: artifact).padding()
        }.frame(width: 393, height: 852).background(Color(.systemBackground))
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
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
            #expect(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let pixels = try #require(image.cgImage?.dataProvider?.data) as Data
        #expect(Set(pixels).count > 16, "The render must contain content, not an empty canvas")
        Attachment.record(image, named: "Signed transaction awaiting broadcast")
        #expect(state.sendFlow.session.selectedEndpoints.isEmpty, "Rendering must not select destinations or submit")
    }

    /// A token send names its token, not the contract that identifies it.
    @Test func tokenSendSummaryNamesTheTokenByCoreSymbol() {
        let state = makeState()
        let contract = "0x1c7d4b196cb0c7b01d743fbc6116a902379c7238"
        state.sendFlow.session.artifact = SendArtifact(id: "token-fixture", revision: 0, stage: .prepared,
            walletId: "fixture", chainId: Chain.ethereumSepolia,
            sender: "0x1111111111111111111111111111111111111111",
            recipient: "0x2222222222222222222222222222222222222222",
            amount: "2.5", asset: contract, symbol: "USDC", createdAt: 0, reviewDigest: "reviewed-content",
            review: SendArtifactReview(warnings: [], recipientWarnings: [], requiresSelfSendConfirmation: false),
            preparedDetails: "", signingPayloadHex: "", signedPayload: nil, transactionHash: nil,
            attempts: [], selectedEndpoints: [])
        let summary = state.pendingHighRiskSendReasons[0]
        #expect(summary.contains("USDC"))
        #expect(!summary.contains(contract))
    }
}
