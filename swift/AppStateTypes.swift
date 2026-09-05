// Nested type declarations for AppState, kept out of AppState.swift so that
// file stays state + orchestration wiring.
//
// Nothing here owns runtime state — just value-type schemas, enums, and the
// typealiases that went with them.

import Foundation

/// Something that happened on a chain. Core records these, caps the list and
/// persists it — this is core's record, not a Swift copy of it.
typealias ChainOperationalEvent = ChainOperationalEventRecord

nonisolated extension ChainOperationalEvent: Identifiable {}

nonisolated extension ChainOperationalEvent {
    typealias Level = ChainOperationalEventLevel
    var timestamp: Date { Date(timeIntervalSince1970: timestampUnix) }
}

nonisolated extension ChainOperationalEventLevel {
    /// The generated enum carries no raw value — the Swift enum it replaced was
    /// `String`-backed and one display site relied on that.
    var displayName: String {
        switch self {
        case .info: return "Info"
        case .warning: return "Warning"
        case .error: return "Error"
        }
    }
}
enum MainAppTab: Hashable {
    case home
    case history
    case staking
    case settings
}

extension AppState {
    enum ResetScope: String, CaseIterable, Identifiable {
        case walletsAndSecrets
        case historyAndCache
        case alertsAndContacts
        case settingsAndEndpoints
        case dashboardCustomization
        case providerState
        var id: String { rawValue }
        @MainActor
        var title: String {
            switch self {
            case .walletsAndSecrets: return localizedStoreString("Wallets & Secrets")
            case .historyAndCache: return localizedStoreString("History & Cache")
            case .alertsAndContacts: return localizedStoreString("Alerts & Contacts")
            case .settingsAndEndpoints: return localizedStoreString("Settings & Endpoints")
            case .dashboardCustomization: return localizedStoreString("Dashboard Customization")
            case .providerState: return localizedStoreString("Provider State")
            }
        }
        @MainActor
        var detail: String {
            switch self {
            case .walletsAndSecrets:
                return localizedStoreString("Imported wallets, seed phrases, watched addresses, and local wallet access data.")
            case .historyAndCache:
                return localizedStoreString("Transactions, history database, diagnostics snapshots, and cached chain state.")
            case .alertsAndContacts: return localizedStoreString("Price alerts, notification rules, and saved address book recipients.")
            case .settingsAndEndpoints:
                return localizedStoreString("Known tokens, pricing and RPC settings, preferences, and icon customizations.")
            case .dashboardCustomization:
                return localizedStoreString("Pinned assets and other home page customization choices stored on this device.")
            case .providerState:
                return localizedStoreString("Provider selections, reliability memory, transport caches, and low-level network heuristics.")
            }
        }
    }

    enum TimeoutError: LocalizedError {
        case timedOut(seconds: Double)
        var errorDescription: String? {
            switch self {
            case .timedOut(let seconds): return "Timed out after \(Int(seconds))s"
            }
        }
    }

    enum SeedPhraseRevealError: LocalizedError {
        case unavailable
        case authenticationRequired
        case passwordRequired
        case invalidPassword
        var errorDescription: String? {
            switch self {
            case .unavailable: return "No seed phrase is stored for this wallet."
            case .authenticationRequired: return "Face ID authentication is required to view this seed phrase."
            case .passwordRequired: return "Enter the wallet password to view this seed phrase."
            case .invalidPassword: return "The wallet password is incorrect."
            }
        }
    }

    enum BackgroundSyncProfile: String, CaseIterable, Identifiable {
        case conservative
        case balanced
        case aggressive
        var id: String { rawValue }
        @MainActor
        var displayName: String {
            switch self {
            case .conservative: return localizedStoreString("Conservative")
            case .balanced: return localizedStoreString("Balanced")
            case .aggressive: return localizedStoreString("Aggressive")
            }
        }
    }

    struct OperationalLogEvent: Codable, Identifiable {
        enum Level: String, Codable { case debug, info, warning, error }
        let id: UUID
        let timestamp: Date
        let level: Level
        let category: String
        let message: String
        let chainName: String?
        let walletID: String?
        let transactionHash: String?
        let source: String?
        let metadata: String?
    }

    struct PendingSelfSendConfirmation {
        let walletID: String
        let chainName: String
        let symbol: String
        let destinationAddressLowercased: String
        let amount: Double
        let createdAt: Date
    }

    struct PerformanceSample: Identifiable, Codable, Equatable {
        let id: UUID
        let operation: String
        let durationMS: Double
        let timestamp: Date
        let metadata: String?
    }

    struct ChainKeypoolState: Codable, Equatable {
        var nextExternalIndex: Int
        var nextChangeIndex: Int
        var reservedReceiveIndex: Int?
    }

    struct ChainOwnedAddressRecord: Codable, Equatable {
        let chainName: String
        let address: String?
        let walletID: String
        let derivationPath: String?
        let index: Int?
        let branch: String?
    }

    struct PendingTransactionStatusResolution {
        let status: TransactionStatus
        let receiptBlockNumber: Int?
        let confirmations: Int?
        let dogecoinNetworkFeeDoge: Double?
    }

    struct ChainDegradedBanner: Identifiable {
        let chainName: String
        let message: String
        let lastGoodSyncAt: Date?
        var id: String { chainName }
    }

    struct PersistedChainSyncState: Codable {
        let version: Int
        let degradedMessages: [String: String]
        let lastGoodSyncUnix: [String: TimeInterval]
        static let currentVersion = 1
    }

    struct DogecoinKeypoolDiagnostic: Identifiable, Equatable {
        let walletID: String
        let walletName: String
        let reservedReceiveIndex: Int?
        let reservedReceivePath: String?
        let reservedReceiveAddress: String?
        let nextExternalIndex: Int
        let nextChangeIndex: Int
        var id: String { walletID }
    }

    struct ChainKeypoolDiagnostic: Identifiable, Equatable {
        let walletID: String
        let walletName: String
        let chainName: String
        let reservedReceiveIndex: Int?
        let reservedReceivePath: String?
        let reservedReceiveAddress: String?
        let nextExternalIndex: Int
        let nextChangeIndex: Int
        var id: String { "\(chainName):\(walletID)" }
    }
}

extension AppState.ChainKeypoolState {
    /// From core's stored keypool row.
    init(keypool: KeypoolState) {
        self.init(
            nextExternalIndex: Int(keypool.nextExternalIndex),
            nextChangeIndex: Int(keypool.nextChangeIndex),
            reservedReceiveIndex: keypool.reservedReceiveIndex.map { Int($0) }
        )
    }

    var coreRecord: ChainKeypoolStateRecord {
        ChainKeypoolStateRecord(
            nextExternalIndex: Int32(nextExternalIndex),
            nextChangeIndex: Int32(nextChangeIndex),
            reservedReceiveIndex: reservedReceiveIndex.map { Int32($0) }
        )
    }
    init(coreRecord: ChainKeypoolStateRecord) {
        self.init(
            nextExternalIndex: Int(coreRecord.nextExternalIndex),
            nextChangeIndex: Int(coreRecord.nextChangeIndex),
            reservedReceiveIndex: coreRecord.reservedReceiveIndex.map { Int($0) }
        )
    }
}

