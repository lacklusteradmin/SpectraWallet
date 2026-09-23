import XCTest
@testable import Spectra

@MainActor
final class WalletImportSessionTests: XCTestCase {
    func testOldSuccessCannotCloseOrClearNewFormOrBusyState() async {
        let session = WalletImportSession()
        session.begin { $0.walletName = "old" }
        let oldGate = ImportSessionGate()
        let newGate = ImportSessionGate()
        var committed = false
        let old = Task {
            await session.submit {
                await oldGate.wait()
                committed = true
                return "old notice"
            }
        }
        _ = await XCTWaiter.fulfillment(of: [oldGate.entered], timeout: 2)
        session.close()
        session.begin { $0.walletName = "new" }
        let current = Task {
            await session.submit { await newGate.wait(); return "new notice" }
        }
        _ = await XCTWaiter.fulfillment(of: [newGate.entered], timeout: 2)
        oldGate.resume()
        let oldCompleted = await old.value
        XCTAssertFalse(oldCompleted)
        XCTAssertTrue(committed, "Closing a form does not erase a core commit")
        XCTAssertTrue(session.isPresented)
        XCTAssertTrue(session.isBusy, "Old defer must not clear the new operation")
        XCTAssertEqual(session.draft.walletName, "new")
        XCTAssertNil(session.error)
        newGate.resume()
        let currentCompleted = await current.value
        XCTAssertTrue(currentCompleted)
        XCTAssertFalse(session.isPresented)
        XCTAssertFalse(session.isBusy)
        XCTAssertEqual(session.error, "new notice")
        XCTAssertEqual(session.draft.walletName, "")
    }

    func testOldFailureCannotOverwriteNewError() async {
        let session = WalletImportSession()
        session.begin { _ in }
        let gate = ImportSessionGate()
        let old = Task {
            await session.submit {
                await gate.wait()
                throw NSError(domain: "old", code: 1)
            }
        }
        _ = await XCTWaiter.fulfillment(of: [gate.entered], timeout: 2)
        // Navigation bindings dismiss by writing this property, not only close().
        session.isPresented = false
        session.begin { $0.walletName = "new" }
        session.error = "current error"
        gate.resume()
        let completed = await old.value
        XCTAssertFalse(completed)
        XCTAssertEqual(session.error, "current error")
        XCTAssertEqual(session.draft.walletName, "new")
        XCTAssertTrue(session.isPresented)
    }

    func testCurrentFailureKeepsFormForRetryAndDismissalClearsSecrets() async {
        let session = WalletImportSession()
        session.begin {
            $0.walletName = "retry"
            $0.overridePassphrase = "sensitive passphrase"
            $0.privateKeyInput = "sensitive key"
            $0.walletPassword = "password"
        }
        let completed = await session.submit {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "failure"])
        }
        XCTAssertFalse(completed)
        XCTAssertEqual(session.error, "failure")
        XCTAssertTrue(session.isPresented)
        XCTAssertFalse(session.isBusy)
        XCTAssertEqual(session.draft.walletName, "retry")
        session.close()
        XCTAssertEqual(session.draft.overridePassphrase, "")
        XCTAssertEqual(session.draft.privateKeyInput, "")
        XCTAssertEqual(session.draft.walletPassword, "")
    }
}

@MainActor
private final class ImportSessionGate {
    let entered = XCTestExpectation(description: "Operation suspended")
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation {
            continuation = $0
            entered.fulfill()
        }
    }
    func resume() { continuation?.resume(); continuation = nil }
}
