import Foundation
import XCTest
@testable import Spectra

// Balance fetch moved to Rust — balance tests live in Core/tests/
@MainActor
final class LitecoinBalanceServiceTests: SpectraNetworkTestCase {}
