import Foundation
import Testing
@testable import Spectra

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct WalletImportSessionTests {
    @Test func oldSuccessCannotCloseOrClearNewFormOrBusyState() async {
        let session = WalletImportSession()
        session.begin { $0.walletName = "old" }
        let oldGate = SuspensionGate<Void>()
        let newGate = SuspensionGate<Void>()
        var committed = false
        let old = Task {
            await session.submit {
                await oldGate.wait()
                committed = true
                return "old notice"
            }
        }
        await oldGate.reached()
        session.close()
        session.begin { $0.walletName = "new" }
        let current = Task {
            await session.submit { await newGate.wait(); return "new notice" }
        }
        await newGate.reached()
        oldGate.resume()
        let oldCompleted = await old.value
        #expect(!oldCompleted)
        #expect(committed, "Closing a form does not erase a core commit")
        #expect(session.isPresented)
        #expect(session.isBusy, "Old defer must not clear the new operation")
        #expect(session.draft.walletName == "new")
        #expect(session.error == nil)
        newGate.resume()
        let currentCompleted = await current.value
        #expect(currentCompleted)
        #expect(!session.isPresented)
        #expect(!session.isBusy)
        #expect(session.error == "new notice")
        #expect(session.draft.walletName == "")
    }

    @Test func oldFailureCannotOverwriteNewError() async {
        let session = WalletImportSession()
        session.begin { _ in }
        let gate = SuspensionGate<Void>()
        let old = Task {
            await session.submit {
                await gate.wait()
                throw NSError(domain: "old", code: 1)
            }
        }
        await gate.reached()
        // Navigation bindings dismiss by writing this property, not only close().
        session.isPresented = false
        session.begin { $0.walletName = "new" }
        session.error = "current error"
        gate.resume()
        let completed = await old.value
        #expect(!completed)
        #expect(session.error == "current error")
        #expect(session.draft.walletName == "new")
        #expect(session.isPresented)
    }

    @Test func currentFailureKeepsFormForRetryAndDismissalClearsSecrets() async {
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
        #expect(!completed)
        #expect(session.error == "failure")
        #expect(session.isPresented)
        #expect(!session.isBusy)
        #expect(session.draft.walletName == "retry")
        session.close()
        #expect(session.draft.overridePassphrase == "")
        #expect(session.draft.privateKeyInput == "")
        #expect(session.draft.walletPassword == "")
    }
}
