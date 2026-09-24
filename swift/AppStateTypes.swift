// Nested type declarations for AppState, kept out of AppState.swift so that
// file stays state + orchestration wiring.
//
// Nothing here owns runtime state — just value-type schemas, enums, and the
// typealiases that went with them.

import Foundation

/// An operational log entry recorded, bounded, and persisted by core.
/// Both the logs screen and chain diagnostics read this record.
nonisolated extension DiagnosticLog: Identifiable {
    var timestamp: Date { Date(timeIntervalSince1970: timestampUnix) }
}

nonisolated extension DiagnosticLogLevel {
    static let allCases: [DiagnosticLogLevel] = [.debug, .info, .warning, .error]
    var displayName: String {
        switch self {
        case .debug: return AppLocalization.string("Debug")
        case .info: return AppLocalization.string("Info")
        case .warning: return AppLocalization.string("Warning")
        case .error: return AppLocalization.string("Error")
        }
    }
    /// The export's tag. Not localized: the export is read by whoever debugs it.
    var exportTag: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        }
    }
}
enum MainAppTab: Hashable {
    case home
    case history
    case staking
    case settings
}

/// What a reset clears. Core's scope, with this app's words for it.
extension ResetScope {
    static let allCases: [ResetScope] = [
        .walletsAndSecrets, .historyAndCache, .alertsAndContacts, .settingsAndEndpoints, .dashboardCustomization,
    ]
    @MainActor
    var title: String {
        switch self {
        case .walletsAndSecrets: return localizedStoreString("Wallets & Secrets")
        case .historyAndCache: return localizedStoreString("History & Cache")
        case .alertsAndContacts: return localizedStoreString("Alerts & Contacts")
        case .settingsAndEndpoints: return localizedStoreString("Settings & Endpoints")
        case .dashboardCustomization: return localizedStoreString("Dashboard Customization")
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
        }
    }
}

extension AppState {
    enum TimeoutError: LocalizedError {
        case timedOut(seconds: Double)
        var errorDescription: String? {
            switch self {
            case .timedOut(let seconds): return AppLocalization.format("Timed out after %llds", Int(seconds))
            }
        }
    }

    enum SeedPhraseRevealError: LocalizedError {
        case unavailable
        case authenticationFailed(String)
        case passwordRequired
        case invalidPassword
        case passwordNotRequired
        var errorDescription: String? {
            switch self {
            case .unavailable: return AppLocalization.string("No seed phrase is stored for this wallet.")
            case .authenticationFailed(let reason): return reason
            case .passwordRequired: return AppLocalization.string("Enter the wallet password to view this seed phrase.")
            case .invalidPassword: return AppLocalization.string("The wallet password is incorrect.")
            case .passwordNotRequired: return AppLocalization.string("This wallet has no password.")
            }
        }
    }

    struct ChainDegradedBanner: Identifiable {
        let chainId: String
        let message: String
        let lastGoodSyncAt: Date?
        var id: String { chainId }
        var chainName: String { Chain.displayName(forId: chainId) }
    }

}

extension KeypoolDiagnostic: Identifiable {
    public var id: String { walletId }
}

