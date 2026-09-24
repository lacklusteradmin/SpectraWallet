import Foundation
#if canImport(XCTest)
    import XCTest
    @testable import Spectra
    @MainActor
    final class WalletDiagnosticsStateTests: IsolatedAppStateTestCase {
        /// Core marks a chain degraded or healthy as part of the refresh that
        /// found it so; this state only adopts what core recorded.
        func testADegradedChainShowsABannerAndSurvivesAReload() async throws {
            _ = try await bridge.applyDiagnosticCommand(
                .degraded(chainId: "ethereum", reason: .failed(message: "Ethereum refresh timed out. Using cached balances and history.")))
            let state = WalletDiagnosticsState(bridge: bridge)
            await state.loadFromSQLite()
            XCTAssertEqual(state.chainDegradedBanners.count, 1)
            XCTAssertEqual(state.chainDegradedBanners.first?.chainId, "ethereum")
            XCTAssertTrue(state.chainDegradedBanners.first?.message.contains("Ethereum refresh timed out.") == true)
            XCTAssertEqual(state.operationalLogs.count, 1)
            XCTAssertEqual(state.operationalLogs.first?.input.level, .warning)
            XCTAssertEqual(state.operationalLogs.first?.input.chainId, "ethereum")
        }
        func testAHealthyChainClearsItsBannerAndLogsTheRecovery() async throws {
            _ = try await bridge.applyDiagnosticCommand(.degraded(chainId: "solana", reason: .historyRefreshFailed))
            _ = try await bridge.applyDiagnosticCommand(.healthy(chainId: "solana"))
            let state = WalletDiagnosticsState(bridge: bridge)
            await state.loadFromSQLite()
            XCTAssertNil(state.chainDegraded["solana"])
            XCTAssertTrue(state.chainDegradedBanners.isEmpty)
            XCTAssertEqual(state.operationalLogs.count, 2)
            XCTAssertEqual(state.operationalLogs.first?.input.level, .info)
            XCTAssertEqual(state.operationalLogs.first?.input.chainId, "solana")
            XCTAssertEqual(state.operationalLogs.first?.input.message, "Chain recovered")
        }
        func testAppendOperationalLogTrimsFieldsAndCapsAtEightHundredEntries() async throws {
            let state = WalletDiagnosticsState(bridge: bridge)
            state.appendOperationalLog(
                .error, category: "  Network  ", message: "  Request failed  ", chainId: "  bitcoin  ", source: "  rpc  ",
                metadata: "  timeout  "
            )
            await state.flushPendingPersistence()
            XCTAssertEqual(state.operationalLogs.first?.input.category, "Network")
            XCTAssertEqual(state.operationalLogs.first?.input.message, "Request failed")
            XCTAssertEqual(state.operationalLogs.first?.input.chainId, "bitcoin")
            XCTAssertEqual(state.operationalLogs.first?.input.source, "rpc")
            XCTAssertEqual(state.operationalLogs.first?.input.metadata, "timeout")
            for index in 0..<810 { state.appendOperationalLog(.info, category: "Load", message: "Event \(index)") }
            await state.flushPendingPersistence()
            XCTAssertEqual(state.operationalLogs.count, 800)
        }
        func testExportOperationalLogsTextIncludesHeaderAndMetadata() async throws {
            let state = WalletDiagnosticsState(bridge: bridge)
            let walletId = UUID()
            state.appendOperationalLog(
                .warning, category: "Chain Sync", message: "Ethereum refresh timed out.", chainId: "ethereum",
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
