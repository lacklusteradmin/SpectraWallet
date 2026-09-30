import Foundation
#if canImport(XCTest)
    import XCTest
    @testable import Spectra
    @MainActor
    final class WalletDiagnosticsStateTests: IsolatedAppStateTestCase {
        /// Core marks a chain degraded or healthy as part of the refresh that
        /// found it so; this state only adopts what core recorded.
        func testADegradedChainShowsABannerAndSurvivesAReload() async throws {
            _ = try await bridge.ready().applyDiagnosticCommand(command: 
                .degraded(chainId: Chain.ethereum, reason: .failed(message: "Ethereum refresh timed out. Using cached balances and history.")))
            let state = WalletDiagnosticsState(bridge: bridge)
            await state.loadFromSQLite()
            XCTAssertEqual(state.chainDegradedBanners.count, 1)
            XCTAssertEqual(state.chainDegradedBanners.first?.chain, Chain.ethereum)
            XCTAssertTrue(state.chainDegradedBanners.first?.message.contains("Ethereum refresh timed out.") == true)
            XCTAssertEqual(state.operationalLogs.count, 1)
            XCTAssertEqual(state.operationalLogs.first?.input.level, .warning)
            XCTAssertEqual(state.operationalLogs.first?.input.chainId, Chain.ethereum)
        }
        func testAHealthyChainClearsItsBannerAndLogsTheRecovery() async throws {
            _ = try await bridge.ready().applyDiagnosticCommand(command: .degraded(chainId: Chain.solana, reason: .historyRefreshFailed))
            _ = try await bridge.ready().applyDiagnosticCommand(command: .healthy(chainId: Chain.solana))
            let state = WalletDiagnosticsState(bridge: bridge)
            await state.loadFromSQLite()
            XCTAssertNil(state.chainDegraded[Chain.solana])
            XCTAssertTrue(state.chainDegradedBanners.isEmpty)
            XCTAssertEqual(state.operationalLogs.count, 2)
            XCTAssertEqual(state.operationalLogs.first?.input.level, .info)
            XCTAssertEqual(state.operationalLogs.first?.input.chainId, Chain.solana)
            XCTAssertEqual(state.operationalLogs.first?.input.message, "Chain recovered")
        }
        /// An appended line crosses the binding with every field. Trimming and
        /// the 800-line cap are core's rules, tested in `operational_events.rs`.
        func testAppendedLogCrossesTheBindingWithEveryField() async throws {
            let state = WalletDiagnosticsState(bridge: bridge)
            state.appendOperationalLog(
                .error, category: "Network", message: "Request failed", chain: Chain.bitcoin, source: "rpc",
                metadata: "timeout"
            )
            await state.flushPendingPersistence()
            XCTAssertEqual(state.operationalLogs.first?.input.category, "Network")
            XCTAssertEqual(state.operationalLogs.first?.input.message, "Request failed")
            XCTAssertEqual(state.operationalLogs.first?.input.chainId, Chain.bitcoin)
            XCTAssertEqual(state.operationalLogs.first?.input.source, "rpc")
            XCTAssertEqual(state.operationalLogs.first?.input.metadata, "timeout")
        }
        func testExportOperationalLogsTextIncludesHeaderAndMetadata() async throws {
            let state = WalletDiagnosticsState(bridge: bridge)
            let walletId = UUID()
            state.appendOperationalLog(
                .warning, category: "Chain Sync", message: "Ethereum refresh timed out.", chain: Chain.ethereum,
                walletId: walletId.uuidString,
                transactionHash: "0xabc", source: "network", metadata: "cached"
            )
            await state.flushPendingPersistence()
            let text = state.exportOperationalLogsText(networkSyncStatusText: "Network Status: Healthy")
            XCTAssertTrue(text.contains("Spectra Operational Logs"))
            XCTAssertTrue(text.contains("Entries: 1"))
            XCTAssertTrue(text.contains("Network Status: Healthy"))
            XCTAssertTrue(text.contains("[WARNING]"))
            XCTAssertTrue(text.contains("wallet=\(walletId.uuidString)"))
            XCTAssertTrue(text.contains("tx=0xabc"))
            XCTAssertTrue(text.contains("meta=cached"))
        }

    }
#endif
