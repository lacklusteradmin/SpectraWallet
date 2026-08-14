import Foundation
import XCTest

@testable import Spectra

/// The same 24 chains are written down six times in the diagnostics code:
/// `StandardDiagnosticsChain`, `chainDiagDescriptors`, `dispatchTable`,
/// `diagnosticsBundleChainNames`, the `diagnosticsJSON(for:)` switch, and the
/// 163 per-chain stored properties behind them.
///
/// Collapsing those tables is the largest remaining piece of Stage 3, and the
/// failure mode it invites is a chain quietly falling out of one list while the
/// others keep it — which is exactly what happened when the 23 JSON wrappers
/// were collapsed and Tron and Solana were dropped. These tests are the net for
/// that work: they say nothing about behaviour, only that the lists agree, and
/// they are meant to fail loudly the moment one of them is edited alone.
@MainActor
final class DiagnosticsChainTableTests: XCTestCase {
    func testEveryDiagnosticsChainHasARunDescriptor() {
        for chain in StandardDiagnosticsChain.allCases {
            XCTAssertNotNil(
                AppState.chainDiagDescriptors[chain],
                "\(chain.rawValue) has no entry in chainDiagDescriptors")
        }
        XCTAssertEqual(
            AppState.chainDiagDescriptors.count, StandardDiagnosticsChain.allCases.count,
            "chainDiagDescriptors has entries for chains the enum does not list")
    }

    func testEveryDiagnosticsChainHasAViewDispatchEntry() {
        for chain in StandardDiagnosticsChain.allCases {
            XCTAssertNotNil(
                StandardDiagnosticsChain.dispatchTable[chain],
                "\(chain.rawValue) has no entry in dispatchTable")
        }
        XCTAssertEqual(
            StandardDiagnosticsChain.dispatchTable.count,
            StandardDiagnosticsChain.allCases.count,
            "dispatchTable has entries for chains the enum does not list")
    }

    /// The bundle names chains by display name and the enum by registry id.
    /// `title` is neither — it is the UI heading ("Bitcoin Diagnostics") — so
    /// the two lists are compared on the id, which is the only spelling both
    /// sides can agree on.
    func testTheBundleListAndTheChainEnumDescribeTheSameSet() {
        let bundleIds = Set(AppState.diagnosticsBundleChainNames.map { coreChainStrIdForName(name: $0) })
        let enumIds = Set(StandardDiagnosticsChain.allCases.map(\.rawValue))
        XCTAssertEqual(
            bundleIds.count, StandardDiagnosticsChain.allCases.count,
            "the bundle list and the chain enum are different sizes")
        XCTAssertEqual(
            bundleIds.symmetricDifference(enumIds), [],
            "the bundle list and the chain enum disagree")
    }

    /// Every id the enum carries has to be a chain the registry knows, so a
    /// registry rename cannot leave a diagnostics entry pointing at nothing.
    func testEveryDiagnosticsChainIdResolvesInTheRegistry() {
        for chain in StandardDiagnosticsChain.allCases {
            XCTAssertFalse(chain.title.isEmpty, "\(chain.rawValue) has no title")
            XCTAssertTrue(
                AppState.diagnosticsBundleChainNames.contains {
                    coreChainStrIdForName(name: $0) == chain.rawValue
                },
                "\(chain.rawValue) is not a chain the bundle reports on")
        }
    }
}
