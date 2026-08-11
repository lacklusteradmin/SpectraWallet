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
        func testMarkChainDegradedCreatesBannerAndPersistsState() async throws {
            let state = WalletDiagnosticsState()
            state.markChainDegraded("Ethereum", detail: "Ethereum refresh timed out. Using cached balances and history.")
            await state.flushPendingPersistence()
            XCTAssertEqual(state.chainDegradedBanners.count, 1)
            XCTAssertEqual(state.chainDegradedBanners.first?.chainName, "Ethereum")
            XCTAssertTrue(state.chainDegradedBanners.first?.message.contains("Ethereum refresh timed out.") == true)
            XCTAssertEqual(state.operationalLogs.count, 1)
            XCTAssertEqual(state.operationalLogs.first?.level, .warning)
            XCTAssertEqual(state.operationalLogs.first?.chainName, "Ethereum")
            let reloaded = WalletDiagnosticsState()
            await reloaded.loadFromSQLite()
            XCTAssertEqual(reloaded.chainDegradedMessages["Ethereum"], state.chainDegradedMessages["Ethereum"])
            XCTAssertEqual(reloaded.operationalLogs.count, 1)
            XCTAssertEqual(reloaded.operationalLogs.first?.chainName, "Ethereum")
        }
        func testMarkChainHealthyClearsBannerAndRecordsRecoveryLog() async throws {
            let state = WalletDiagnosticsState()
            state.markChainDegraded("Solana", detail: "Solana history refresh failed. Using cached history.")
            state.markChainHealthy("Solana")
            await state.flushPendingPersistence()
            XCTAssertTrue(state.chainDegradedMessages["Solana"] == nil)
            XCTAssertNotNil(state.lastGoodChainSyncByName["Solana"])
            XCTAssertEqual(state.operationalLogs.count, 2)
            XCTAssertEqual(state.operationalLogs.first?.level, .info)
            XCTAssertEqual(state.operationalLogs.first?.chainName, "Solana")
            XCTAssertEqual(state.operationalLogs.first?.message, "Chain recovered")
        }
        func testAppendOperationalLogTrimsFieldsAndCapsAtEightHundredEntries() async throws {
            let state = WalletDiagnosticsState()
            state.appendOperationalLog(
                .error, category: "  Network  ", message: "  Request failed  ", chainName: "  Bitcoin  ", source: "  rpc  ",
                metadata: "  timeout  "
            )
            XCTAssertEqual(state.operationalLogs.first?.category, "Network")
            XCTAssertEqual(state.operationalLogs.first?.message, "Request failed")
            XCTAssertEqual(state.operationalLogs.first?.chainName, "Bitcoin")
            XCTAssertEqual(state.operationalLogs.first?.source, "rpc")
            XCTAssertEqual(state.operationalLogs.first?.metadata, "timeout")
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
            try? await WalletServiceBridge.shared.saveState(key: WalletDiagnosticsState.chainSyncStateDefaultsKey, stateJSON: "{}")
            try? await WalletServiceBridge.shared.saveState(key: WalletDiagnosticsState.operationalLogsDefaultsKey, stateJSON: "{}")
        }
    }
#endif
