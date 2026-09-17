import Foundation
#if canImport(XCTest)
    import XCTest
    @testable import Spectra
    @MainActor
    final class WalletDiagnosticsStateTests: XCTestCase {
        override func setUp() async throws {
            try await super.setUp()
            await clearDiagnosticsSQLite()
        }
        override func tearDown() async throws {
            await clearDiagnosticsSQLite()
            try await super.tearDown()
        }
        /// Core marks a chain degraded or healthy as part of the refresh that
        /// found it so; this state only adopts what core recorded.
        func testADegradedChainShowsABannerAndSurvivesAReload() async throws {
            _ = try await WalletServiceBridge.shared.applyDiagnosticCommand(
                .degraded(chainName: "Ethereum", detail: "Ethereum refresh timed out. Using cached balances and history."))
            let state = WalletDiagnosticsState()
            await state.loadFromSQLite()
            XCTAssertEqual(state.chainDegradedBanners.count, 1)
            XCTAssertEqual(state.chainDegradedBanners.first?.chainName, "Ethereum")
            XCTAssertTrue(state.chainDegradedBanners.first?.message.contains("Ethereum refresh timed out.") == true)
            XCTAssertEqual(state.operationalLogs.count, 1)
            XCTAssertEqual(state.operationalLogs.first?.input.level, .warning)
            XCTAssertEqual(state.operationalLogs.first?.input.chainName, "Ethereum")
        }
        func testAHealthyChainClearsItsBannerAndLogsTheRecovery() async throws {
            _ = try await WalletServiceBridge.shared.applyDiagnosticCommand(
                .degraded(chainName: "Solana", detail: "Solana history refresh failed. Using cached history."))
            _ = try await WalletServiceBridge.shared.applyDiagnosticCommand(.healthy(chainName: "Solana"))
            let state = WalletDiagnosticsState()
            await state.loadFromSQLite()
            XCTAssertTrue(state.chainDegradedMessages["Solana"] == nil)
            XCTAssertNotNil(state.lastGoodChainSyncByName["Solana"])
            XCTAssertEqual(state.operationalLogs.count, 2)
            XCTAssertEqual(state.operationalLogs.first?.input.level, .info)
            XCTAssertEqual(state.operationalLogs.first?.input.chainName, "Solana")
            XCTAssertEqual(state.operationalLogs.first?.input.message, "Chain recovered")
        }
        func testAppendOperationalLogTrimsFieldsAndCapsAtEightHundredEntries() async throws {
            let state = WalletDiagnosticsState()
            state.appendOperationalLog(
                .error, category: "  Network  ", message: "  Request failed  ", chainName: "  Bitcoin  ", source: "  rpc  ",
                metadata: "  timeout  "
            )
            await state.flushPendingPersistence()
            XCTAssertEqual(state.operationalLogs.first?.input.category, "Network")
            XCTAssertEqual(state.operationalLogs.first?.input.message, "Request failed")
            XCTAssertEqual(state.operationalLogs.first?.input.chainName, "Bitcoin")
            XCTAssertEqual(state.operationalLogs.first?.input.source, "rpc")
            XCTAssertEqual(state.operationalLogs.first?.input.metadata, "timeout")
            for index in 0..<810 { state.appendOperationalLog(.info, category: "Load", message: "Event \(index)") }
            await state.flushPendingPersistence()
            XCTAssertEqual(state.operationalLogs.count, 800)
        }
        func testExportOperationalLogsTextIncludesHeaderAndMetadata() async throws {
            let state = WalletDiagnosticsState()
            let walletID = UUID()
            state.appendOperationalLog(
                .warning, category: "Chain Sync", message: "Ethereum refresh timed out.", chainName: "Ethereum",
                walletID: walletID.uuidString,
                transactionHash: "0xabc", source: "network", metadata: "cached"
            )
            await state.flushPendingPersistence()
            let text = state.exportOperationalLogsText(networkSyncStatusText: "Network Status: Healthy")
            XCTAssertTrue(text.contains("Spectra Operational Logs"))
            XCTAssertTrue(text.contains("Entries: 1"))
            XCTAssertTrue(text.contains("Network Status: Healthy"))
            XCTAssertTrue(text.contains("[WARNING]"))
            XCTAssertTrue(text.contains("wallet=\(walletID.uuidString)"))
            XCTAssertTrue(text.contains("tx=0xabc"))
            XCTAssertTrue(text.contains("meta=cached"))
        }
        private func clearDiagnosticsSQLite() async {
            _ = try? await WalletServiceBridge.shared.applyDiagnosticCommand(.reset)
        }
    }
#endif
