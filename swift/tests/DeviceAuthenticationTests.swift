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
}
