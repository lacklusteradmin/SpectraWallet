import XCTest
import SwiftUI
@testable import Spectra

@MainActor
final class SendStagesBridgeTests: IsolatedAppStateTestCase {
    func testMoneroSyncStatusAndAuthorizationCrossTheBridge() async throws {
        let wallet = WalletView(name: "Local XMR", chainId: "monero", addresses: ["monero":
            "48ZFsbBKZAnN9Tyw7XsCakJ4dBxBpaD3wa9Az6V5ZwAK99kYQzcgckSNVv5iZhMp8o37fhNzY7eM2ERGoTWr4B282s4mcDi"],
            signing: .seedPhrase(passwordProtected: false))
        _ = try await bridge.ready().applyStateCommand(command: .upsertWallet(wallet: wallet.walletState()))
        let status = try await bridge.ready().moneroSyncStatus(walletId: wallet.id)
        XCTAssertEqual(status?.scannedHeight, 0)
        XCTAssertEqual(status?.complete, false)
        do {
            _ = try await bridge.ready().syncMoneroWallet(walletId: wallet.id, password: nil, restoreHeight: nil)
            XCTFail("Sync requires the locally owned signing keys")
        } catch {
            let after = try await bridge.ready().moneroSyncStatus(walletId: wallet.id)
            XCTAssertEqual(after?.scannedHeight, 0)
        }
    }

    func testStageStorageAndRefusalsCrossTheAsyncRuntime() async throws {
        let artifacts = try await bridge.ready().listSends()
        XCTAssertTrue(artifacts.isEmpty)
        do {
            _ = try await bridge.ready().buildOwnedSend(input: SendReviewInput(walletId: "missing",
                holdingKey: "ethereum:native", amount: "1", destination: "0x1111111111111111111111111111111111111111", overrides: nil))
            XCTFail("Building requires a core-owned wallet and holding")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("wallet"))
        }
        do {
            _ = try await bridge.ready().signSend(id: "missing", reviewDigest: "changed", password: nil)
            XCTFail("A caller cannot sign an artifact core does not own")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("artifact not found"))
        }
        do {
            _ = try await bridge.ready().broadcastSend(id: "missing", endpoints: ["http://127.0.0.1:1"])
            XCTFail("A caller cannot submit arbitrary content")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("artifact not found"))
        }
        let reopened = WalletServiceBridge(databasePath: directory.appendingPathComponent("state.sqlite").path,
            service: try WalletService(endpoints: []))
        _ = try await reopened.openState()
        let restored = try await reopened.ready().listSends()
        XCTAssertTrue(restored.isEmpty)
    }

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
