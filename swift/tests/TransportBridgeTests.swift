import XCTest
@testable import Spectra

@MainActor
final class TransportBridgeTests: XCTestCase {
    func testStoredTransportChangesTakeEffectWithoutSwiftLifecycleDecisions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = try WalletService(endpoints: [])
        _ = try await service.openState(databasePath: directory.appendingPathComponent("state.db").path)
        _ = try await service.applyStateCommand(command: .setAppSetting(update: .torUseCustomProxy(value: true)))
        _ = try await service.applyStateCommand(command: .setAppSetting(update: .torEnabled(value: true)))
        let status = try await service.configureNetworkRuntime(cacheDir: directory.path)
        XCTAssertEqual(status, .ready)
        _ = try await service.applyStateCommand(command: .setAppSetting(update: .torCustomProxyAddress(value: "socks5h://127.0.0.1:9999")))
        let reconnected = await service.reconnectTor()
        XCTAssertEqual(reconnected, .ready)
        _ = try await service.resetData(scopes: [.settingsAndEndpoints])
        XCTAssertEqual(torStatus(), .stopped)
    }
}
