import XCTest
@testable import Spectra

@MainActor
final class SendSessionTests: XCTestCase {
    private func artifact(_ id: String, stage: SendStage = .prepared) -> SendArtifact {
        SendArtifact(id: id, revision: 0, stage: stage, walletId: "wallet", chainId: id,
            sender: "sender", recipient: "recipient", amount: "1.000000000000000001", asset: "ETH",
            createdAt: 0, reviewDigest: "digest-\(id)",
            review: SendArtifactReview(warnings: [.newAddress], recipientWarnings: [], requiresSelfSendConfirmation: true),
            preparedDetails: "exact transaction", signingPayloadHex: "", signedPayload: nil,
            transactionHash: nil, attempts: [], selectedEndpoints: [])
    }

    func testLateEndpointResponseCannotMixTwoResumedArtifacts() async {
        let session = SendSession()
        let oldGate = SendSessionGate<[String]>()
        let newGate = SendSessionGate<[String]>()
        let old = Task {
            await session.load(operation: .resume, prepare: { self.artifact("old") },
                endpoints: { _ in await oldGate.wait() })
        }
        _ = await XCTWaiter.fulfillment(of: [oldGate.entered], timeout: 2)
        XCTAssertNil(session.artifact, "Do not expose an artifact before its endpoints arrive")
        session.reset()
        let current = Task {
            await session.load(operation: .resume, prepare: { self.artifact("new") },
                endpoints: { _ in await newGate.wait() })
        }
        _ = await XCTWaiter.fulfillment(of: [newGate.entered], timeout: 2)
        oldGate.resume(["old-node"])
        let oldAdopted = await old.value
        XCTAssertFalse(oldAdopted)
        XCTAssertEqual(session.operation, .resume, "Old cleanup must not clear the new request's busy state")
        newGate.resume(["new-node"])
        let adopted = await current.value
        XCTAssertTrue(adopted)
        XCTAssertEqual(session.artifact?.id, "new")
        XCTAssertEqual(session.endpoints, ["new-node"])
        XCTAssertNil(session.operation)
    }

    func testClosingDuringAuthenticationNeverCallsSigner() async {
        let session = SendSession()
        session.artifact = artifact("old")
        let authentication = SendSessionGate<String?>()
        var signed = false
        let work = Task {
            await session.sign(password: nil, authenticate: { await authentication.wait() }, sign: { _, _, _ in
                signed = true
                return self.artifact("old", stage: .signed)
            })
        }
        _ = await XCTWaiter.fulfillment(of: [authentication.entered], timeout: 2)
        session.reset()
        session.artifact = artifact("new")
        authentication.resume(nil)
        await work.value
        XCTAssertFalse(signed)
        XCTAssertEqual(session.artifact?.id, "new")
        XCTAssertNil(session.error)
    }

    func testClosedBuildFailureCannotOverwriteNewSessionError() async {
        let session = SendSession()
        let gate = SendSessionGate<Bool>()
        let work = Task {
            await session.load(operation: .build, prepare: {
                _ = await gate.wait()
                throw NSError(domain: "obsolete", code: 1)
            }, endpoints: { _ in XCTFail("Failed builds have no endpoints"); return [] })
        }
        _ = await XCTWaiter.fulfillment(of: [gate.entered], timeout: 2)
        session.reset()
        session.error = "current error"
        gate.resume(true)
        let adopted = await work.value
        XCTAssertFalse(adopted)
        XCTAssertEqual(session.error, "current error")
        XCTAssertNil(session.artifact)
    }

    func testBroadcastCompletionAfterCloseStillReturnsCommittedResultWithoutReopeningArtifact() async {
        let session = SendSession()
        session.artifact = artifact("old", stage: .signed)
        session.endpoints = ["selected", "unselected"]
        session.selectedEndpoints = ["selected"]
        let gate = SendSessionGate<Bool>()
        let work = Task {
            await session.broadcast { id, endpoints in
                XCTAssertEqual(id, "old")
                XCTAssertEqual(endpoints, ["selected"])
                _ = await gate.wait()
                return self.artifact("old", stage: .signed)
            }
        }
        _ = await XCTWaiter.fulfillment(of: [gate.entered], timeout: 2)
        session.reset()
        session.artifact = artifact("new")
        session.error = "New session error"
        gate.resume(true)
        let result = await work.value
        XCTAssertEqual(result?.id, "old", "Application completion must run even after the composer closes")
        XCTAssertEqual(session.artifact?.id, "new")
        XCTAssertEqual(session.error, "New session error")
    }
    func testBroadcastCompletionRefreshesApplicationAfterComposerIsReplaced() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = try WalletService(endpoints: [])
        let bridge = WalletServiceBridge(databasePath: directory.appendingPathComponent("state.sqlite").path, service: service)
        _ = try await bridge.openState()
        let store = AppState(bridge: bridge, startServices: false)
        let wallet = WalletView(name: "Sender", chainId: "ethereum", addresses: ["ethereum": "0x1111111111111111111111111111111111111111"])
        _ = try await bridge.ready().applyStateCommand(command: .upsertWallet(wallet: wallet.walletState()))
        store.sendFlow.session.artifact = artifact("old", stage: .signed)
        let gate = SendSessionGate<Bool>()
        let work = Task {
            guard let result = await store.sendFlow.session.broadcast(submit: { _, _ in
                _ = await gate.wait()
                let record = TransactionRecord(id: "old", walletId: wallet.id, kind: .send, status: .pending,
                    walletName: wallet.name, assetDisplayName: "Ether", symbol: "ETH", chainId: "ethereum",
                    amount: "1", address: "0x2222222222222222222222222222222222222222")
                _ = try await service.applyTransactionCommand(command: .upsert(records: [record]))
                return self.artifact("old", stage: .signed)
            }) else { return }
            await store.handleBroadcastCompletion(result)
        }
        _ = await XCTWaiter.fulfillment(of: [gate.entered], timeout: 2)
        store.sendFlow.reset()
        store.sendFlow.session.artifact = artifact("new")
        gate.resume(true)
        await work.value
        XCTAssertEqual(store.transactions.map(\.id), ["old"])
        XCTAssertEqual(store.transactionCount, 1)
        XCTAssertEqual(store.sendFlow.artifact?.id, "new")
    }

}

@MainActor
private final class SendSessionGate<Value: Sendable> {
    let entered = XCTestExpectation(description: "Reached suspension point")
    private var continuation: CheckedContinuation<Value, Never>?
    func wait() async -> Value {
        await withCheckedContinuation {
            continuation = $0
            entered.fulfill()
        }
    }
    func resume(_ value: Value) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
