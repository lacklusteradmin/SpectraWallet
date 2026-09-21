import Foundation
import XCTest
@testable import Spectra

@MainActor
class IsolatedAppStateTestCase: XCTestCase {
    var bridge: WalletServiceBridge!
    var service: WalletService!
    var directory: URL!
    private var states: [AppState] = []

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        service = try WalletService(endpoints: [])
        service.setSecretStore(store: TestSecretStore())
        bridge = WalletServiceBridge(databasePath: directory.appendingPathComponent("state.sqlite").path, service: service)
        _ = try await bridge.openState()
    }

    func makeState() -> AppState {
        let state = AppState(bridge: bridge, startServices: false)
        states.append(state)
        return state
    }

    override func tearDown() async throws {
        for state in states {
            await state.awaitPendingSettingCommands()
            await state.awaitPendingAddressBookCommands()
            await state.walletMutationTask?.value
            await state.diagnostics.flushPendingPersistence()
        }
        states.removeAll()
        bridge = nil
        service = nil
        try FileManager.default.removeItem(at: directory)
        directory = nil
        try await super.tearDown()
    }
}

final class TestSecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [SecretClass: [String: String]] = [:]
    func loadSecret(kind: SecretClass, key: String) throws -> String {
        try lock.withLock {
            guard let value = values[kind]?[key] else { throw SecretStoreError.NotFound }
            return value
        }
    }
    func saveSecret(kind: SecretClass, key: String, value: String) throws {
        lock.withLock { values[kind, default: [:]][key] = value }
    }
    func deleteSecret(kind: SecretClass, key: String) throws {
        lock.withLock { _ = values[kind]?.removeValue(forKey: key) }
    }
}
