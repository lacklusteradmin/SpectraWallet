import XCTest
@testable import Spectra

@MainActor
final class DeviceAuthenticationTests: XCTestCase {
    func testDisablingSendAuthenticationDoesNotDisableOtherProtectedActions() {
        for action in [DeviceAuthenticationAction.unlock, .deleteWallet, .resetData] {
            XCTAssertTrue(action.requiresAuthentication(useFaceId: true, authenticateSends: false))
        }
        XCTAssertFalse(DeviceAuthenticationAction.send.requiresAuthentication(useFaceId: true, authenticateSends: false))
        XCTAssertTrue(DeviceAuthenticationAction.send.requiresAuthentication(useFaceId: true, authenticateSends: true))
    }

    func testRevealingASeedPhraseAlwaysRequiresAuthentication() {
        for useFaceId in [true, false] {
            for authenticateSends in [true, false] {
                XCTAssertTrue(DeviceAuthenticationAction.revealSeedPhrase.requiresAuthentication(
                    useFaceId: useFaceId, authenticateSends: authenticateSends))
            }
        }
    }
}
