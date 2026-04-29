import Foundation

// MARK: - Responsibility
//
// This file holds **address-resolution logic only**: given a wallet,
// return a derived/stored address for a particular chain. No UI state
// (no `isResolving…` flags, no `receive…` mutations, no presentation
// helpers) lives here. UI state for the receive flow lives in
// `AppState+ReceiveFlow.swift`; mixing the two was a known god-object
// problem flagged in the readability audit.
//
// Convention for new methods in this file: pure read of wallet + AppState
// derivation context; return an optional `String` address; no side
// effects. If a method needs to flip a UI flag, it belongs in
// `AppState+ReceiveFlow` and should *call* into one of these resolvers,
// not own the resolution logic itself.

/// Pure derivation classification — no `AppState` reads, no mutation.
/// Lifted out as a free function so callers and tests don't need to
/// instantiate `AppState`. Exemplar for the testability convention
/// documented in `Store+Formatting.swift`.
func classifySolanaDerivationPreference(
    for wallet: ImportedWallet,
    using resolution: SeedDerivationResolution
) -> SolanaDerivationPreference {
    resolution.flavor == .legacy ? .legacy : .standard
}

@MainActor
extension AppState {
    /// Thin shim: pulls the resolution off `self` and forwards to the
    /// pure free function. Kept for call-site ergonomics.
    func solanaDerivationPreference(for wallet: ImportedWallet) -> SolanaDerivationPreference {
        let resolution = derivationResolution(for: wallet, chain: .solana)
        return classifySolanaDerivationPreference(for: wallet, using: resolution)
    }

    func resolvedEthereumAddress(for wallet: ImportedWallet) -> String? { resolvedEVMAddress(for: wallet, chainName: "Ethereum") }

    func resolvedEVMAddress(for wallet: ImportedWallet, chainName: String) -> String? {
        guard isEVMChain(chainName), evmChainContext(for: chainName) != nil else { return nil }
        if let seedPhrase = storedSeedPhrase(for: wallet.id),
            let derivationChain = WalletDerivationLayer.evmSeedDerivationChain(for: chainName),
            let derived = try? WalletDerivationLayer.deriveAddress(
                seedPhrase: seedPhrase, chain: derivationChain,
                derivationPath: walletDerivationPath(for: wallet, chain: derivationChain))
        {
            return derived
        }
        if let addr = wallet.ethereumAddress, !addr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AddressValidation.normalized(addr, kind: "evm")
        }
        return nil
    }

    func resolvedBitcoinAddress(for wallet: ImportedWallet) -> String? {
        let networkMode = bitcoinNetworkMode(for: wallet)
        let chain: SeedDerivationChain = bitcoinDerivationChain(for: networkMode)
        return resolveDerivedOrStoredAddress(
            for: wallet, chain: chain,
            derivationPath: walletDerivationPath(for: wallet, chain: chain),
            storedAddress: wallet.bitcoinAddress,
            validationKind: bitcoinValidationKind(for: networkMode), validationNetworkMode: nil
        )
    }

    func resolvedDogecoinAddress(for wallet: ImportedWallet) -> String? {
        let networkMode = dogecoinNetworkMode(for: wallet)
        let chain: SeedDerivationChain = networkMode == .testnet ? .dogecoinTestnet : .dogecoin
        let derivationPath = WalletDerivationPath.dogecoin(
            account: derivationAccount(for: wallet, chain: chain), branch: .external, index: 0
        )
        return resolveDerivedOrStoredAddress(
            for: wallet, chain: chain,
            derivationPath: derivationPath, storedAddress: wallet.dogecoinAddress,
            validationKind: networkMode == .testnet ? "dogecoinTestnet" : "dogecoin", validationNetworkMode: nil
        )
    }

    private func bitcoinDerivationChain(for mode: BitcoinNetworkMode) -> SeedDerivationChain {
        switch mode {
        case .mainnet: return .bitcoin
        case .testnet: return .bitcoinTestnet
        case .testnet4: return .bitcoinTestnet4
        case .signet: return .bitcoinSignet
        }
    }

    private func bitcoinValidationKind(for mode: BitcoinNetworkMode) -> String {
        switch mode {
        case .mainnet: return "bitcoin"
        case .testnet: return "bitcoinTestnet"
        case .testnet4: return "bitcoinTestnet4"
        case .signet: return "bitcoinSignet"
        }
    }

    func resolvedTronAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .tron, derivationPath: wallet.seedDerivationPaths.tron,
            storedAddress: wallet.tronAddress, validationKind: "tron"
        )
    }

    func resolvedSolanaAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .solana, derivationPath: walletDerivationPath(for: wallet, chain: .solana),
            storedAddress: wallet.solanaAddress, validationKind: "solana"
        )
    }

    func resolvedSuiAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .sui, derivationPath: walletDerivationPath(for: wallet, chain: .sui),
            storedAddress: wallet.suiAddress, validationKind: "sui", normalizeStored: true
        )
    }

    func resolvedAptosAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .aptos, derivationPath: walletDerivationPath(for: wallet, chain: .aptos),
            storedAddress: wallet.aptosAddress, validationKind: "aptos", normalizeStored: true
        )
    }

    func resolvedTONAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .ton, derivationPath: walletDerivationPath(for: wallet, chain: .ton),
            storedAddress: wallet.tonAddress, validationKind: "ton", normalizeStored: true
        )
    }

    func resolvedICPAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .internetComputer, derivationPath: wallet.seedDerivationPaths.internetComputer,
            storedAddress: wallet.icpAddress, validationKind: "internetComputer", normalizeStored: true
        )
    }

    func resolvedNearAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .near, derivationPath: walletDerivationPath(for: wallet, chain: .near),
            storedAddress: wallet.nearAddress, validationKind: "near",
            derivedPostProcess: .lowercase, normalizeStored: true
        )
    }

    func resolvedPolkadotAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .polkadot, derivationPath: wallet.seedDerivationPaths.polkadot,
            storedAddress: wallet.polkadotAddress, validationKind: "polkadot",
            derivedPostProcess: .trim
        )
    }

    func resolvedZcashAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .zcash, derivationPath: wallet.seedDerivationPaths.zcash,
            storedAddress: wallet.zcashAddress, validationKind: "zcash"
        )
    }

    func resolvedBitcoinGoldAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .bitcoinGold, derivationPath: wallet.seedDerivationPaths.bitcoinGold,
            storedAddress: wallet.bitcoinGoldAddress, validationKind: "bitcoinGold"
        )
    }

    func resolvedDecredAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .decred, derivationPath: wallet.seedDerivationPaths.decred,
            storedAddress: wallet.decredAddress, validationKind: "decred"
        )
    }

    func resolvedKaspaAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .kaspa, derivationPath: wallet.seedDerivationPaths.kaspa,
            storedAddress: wallet.kaspaAddress, validationKind: "kaspa",
            derivedPostProcess: .lowercase, normalizeStored: true
        )
    }

    func resolvedDashAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .dash, derivationPath: wallet.seedDerivationPaths.dash,
            storedAddress: wallet.dashAddress, validationKind: "dash"
        )
    }

    func resolvedBittensorAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .bittensor, derivationPath: wallet.seedDerivationPaths.bittensor,
            storedAddress: wallet.bittensorAddress, validationKind: "bittensor",
            derivedPostProcess: .trim
        )
    }

    func resolvedStellarAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .stellar, derivationPath: wallet.seedDerivationPaths.stellar,
            storedAddress: wallet.stellarAddress, validationKind: "stellar",
            derivedPostProcess: .trim
        )
    }

    func resolvedCardanoAddress(for wallet: ImportedWallet) -> String? {
        if let addr = wallet.cardanoAddress, AddressValidation.isValid(addr, kind: "cardano") {
            return addr.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let seedPhrase = storedSeedPhrase(for: wallet.id),
            let derived = try? WalletDerivationLayer.deriveAddress(
                seedPhrase: seedPhrase, chain: .cardano,
                derivationPath: walletDerivationPath(for: wallet, chain: .cardano)),
            AddressValidation.isValid(derived, kind: "cardano")
        {
            return derived
        }
        return nil
    }

    func resolvedXRPAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .xrp, derivationPath: walletDerivationPath(for: wallet, chain: .xrp),
            storedAddress: wallet.xrpAddress, validationKind: "xrp"
        )
    }

    func resolvedMoneroAddress(for wallet: ImportedWallet) -> String? {
        guard let addr = wallet.moneroAddress, AddressValidation.isValid(addr, kind: "monero") else { return nil }
        return addr.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func resolvedLitecoinAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .litecoin, derivationPath: walletDerivationPath(for: wallet, chain: .litecoin),
            storedAddress: wallet.litecoinAddress, validationKind: "litecoin"
        )
    }

    func resolvedBitcoinCashAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .bitcoinCash, derivationPath: walletDerivationPath(for: wallet, chain: .bitcoinCash),
            storedAddress: wallet.bitcoinCashAddress, validationKind: "bitcoinCash"
        )
    }

    func resolvedBitcoinSVAddress(for wallet: ImportedWallet) -> String? {
        resolveDerivedOrStoredAddress(
            for: wallet, chain: .bitcoinSV, derivationPath: walletDerivationPath(for: wallet, chain: .bitcoinSV),
            storedAddress: wallet.bitcoinSvAddress, validationKind: "bitcoinSV"
        )
    }

    func resolvedAddress(for wallet: ImportedWallet, chainName: String) -> String? {
        switch chainName {
        case "Bitcoin": return resolvedBitcoinAddress(for: wallet)
        case "Bitcoin Cash": return resolvedBitcoinCashAddress(for: wallet)
        case "Bitcoin SV": return resolvedBitcoinSVAddress(for: wallet)
        case "Litecoin": return resolvedLitecoinAddress(for: wallet)
        case "Dogecoin": return resolvedDogecoinAddress(for: wallet)
        case "Tron": return resolvedTronAddress(for: wallet)
        case "Solana": return resolvedSolanaAddress(for: wallet)
        case "Stellar": return resolvedStellarAddress(for: wallet)
        case "XRP Ledger": return resolvedXRPAddress(for: wallet)
        case "Monero": return resolvedMoneroAddress(for: wallet)
        case "Cardano": return resolvedCardanoAddress(for: wallet)
        case "Sui": return resolvedSuiAddress(for: wallet)
        case "Aptos": return resolvedAptosAddress(for: wallet)
        case "TON": return resolvedTONAddress(for: wallet)
        case "Internet Computer": return resolvedICPAddress(for: wallet)
        case "NEAR": return resolvedNearAddress(for: wallet)
        case "Polkadot": return resolvedPolkadotAddress(for: wallet)
        case "Zcash": return resolvedZcashAddress(for: wallet)
        case "Bitcoin Gold": return resolvedBitcoinGoldAddress(for: wallet)
        case "Decred": return resolvedDecredAddress(for: wallet)
        case "Kaspa": return resolvedKaspaAddress(for: wallet)
        case "Dash": return resolvedDashAddress(for: wallet)
        case "Bittensor": return resolvedBittensorAddress(for: wallet)
        default:
            if isEVMChain(chainName) { return resolvedEVMAddress(for: wallet, chainName: chainName) }
            return nil
        }
    }

    func walletWithResolvedDogecoinAddress(_ wallet: ImportedWallet) -> ImportedWallet {
        ImportedWallet(
            id: wallet.id, name: wallet.name, bitcoinNetworkMode: wallet.bitcoinNetworkMode,
            dogecoinNetworkMode: wallet.dogecoinNetworkMode, bitcoinAddress: wallet.bitcoinAddress,
            bitcoinXpub: wallet.bitcoinXpub, bitcoinCashAddress: wallet.bitcoinCashAddress,
            bitcoinSvAddress: wallet.bitcoinSvAddress, litecoinAddress: wallet.litecoinAddress,
            dogecoinAddress: resolvedDogecoinAddress(for: wallet) ?? wallet.dogecoinAddress,
            ethereumAddress: wallet.ethereumAddress, tronAddress: wallet.tronAddress,
            solanaAddress: wallet.solanaAddress, stellarAddress: wallet.stellarAddress,
            xrpAddress: wallet.xrpAddress, moneroAddress: wallet.moneroAddress,
            cardanoAddress: wallet.cardanoAddress, suiAddress: wallet.suiAddress,
            aptosAddress: wallet.aptosAddress, tonAddress: wallet.tonAddress,
            icpAddress: wallet.icpAddress, nearAddress: wallet.nearAddress,
            polkadotAddress: wallet.polkadotAddress, zcashAddress: wallet.zcashAddress,
            bitcoinGoldAddress: wallet.bitcoinGoldAddress,
            decredAddress: wallet.decredAddress, kaspaAddress: wallet.kaspaAddress,
            dashAddress: wallet.dashAddress,
            bittensorAddress: wallet.bittensorAddress,
            seedDerivationPreset: wallet.seedDerivationPreset,
            seedDerivationPaths: wallet.seedDerivationPaths,
            derivationOverrides: wallet.derivationOverrides,
            selectedChain: wallet.selectedChain,
            holdings: wallet.holdings, includeInPortfolioTotal: wallet.includeInPortfolioTotal
        )
    }

    private func resolveDerivedOrStoredAddress(
        for wallet: ImportedWallet,
        chain: SeedDerivationChain,
        derivationPath: String,
        storedAddress: String?,
        validationKind: String,
        validationNetworkMode: String? = nil,
        derivedPostProcess: DerivedAddressPostProcess = .none,
        normalizeStored: Bool = false
    ) -> String? {
        let derived: String? = {
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else { return nil }
            return try? WalletDerivationLayer.deriveAddress(
                seedPhrase: seedPhrase, chain: chain, derivationPath: derivationPath
            )
        }()
        return corePlanResolveDerivedOrStoredAddress(
            derived: derived, stored: storedAddress, validationKind: validationKind,
            validationNetworkMode: validationNetworkMode, derivedPostProcess: derivedPostProcess,
            normalizeStored: normalizeStored
        )
    }
}
/// Pure-function cache for `coreValidateAddress` / `coreValidateStringIdentifier`.
///
/// `AddressValidation.isValid` / `normalized` used to hit a Rust FFI call
/// **per keystroke** in the watch-only setup flow, the address-book form,
/// the send form, etc. — via SwiftUI body re-evaluations even when the
/// input text didn't actually change. Results are deterministic in their
/// inputs, so we memoize them and cap the cache at a small size so user
/// input can't grow it unbounded.
nonisolated private final class AddressValidationCache: @unchecked Sendable {
    static let shared = AddressValidationCache()
    private let lock = NSLock()
    private var addressCache: [String: AddressValidationResult] = [:]
    private var stringCache: [String: StringValidationResult] = [:]
    private static let maxEntries = 512
    private init() {}
    func address(_ address: String, kind: String, networkMode: String?) -> AddressValidationResult {
        let key = "\(kind)|\(networkMode ?? "")|\(address)"
        lock.lock()
        if let cached = addressCache[key] { lock.unlock(); return cached }
        lock.unlock()
        let result = coreValidateAddress(request: AddressValidationRequest(kind: kind, value: address, networkMode: networkMode))
        lock.lock()
        defer { lock.unlock() }
        if addressCache.count > Self.maxEntries {
            addressCache.removeAll(keepingCapacity: true)
        }
        addressCache[key] = result
        return result
    }
    func string(_ value: String, kind: String) -> StringValidationResult {
        let key = "\(kind)|\(value)"
        lock.lock()
        if let cached = stringCache[key] { lock.unlock(); return cached }
        lock.unlock()
        let result = coreValidateStringIdentifier(request: StringValidationRequest(kind: kind, value: value))
        lock.lock()
        defer { lock.unlock() }
        if stringCache.count > Self.maxEntries {
            stringCache.removeAll(keepingCapacity: true)
        }
        stringCache[key] = result
        return result
    }
}

enum AddressValidation {
    nonisolated static func isValid(_ address: String, kind: String, networkMode: String? = nil) -> Bool {
        AddressValidationCache.shared.address(address, kind: kind, networkMode: networkMode).isValid
    }
    nonisolated static func normalized(_ address: String, kind: String, networkMode: String? = nil) -> String? {
        AddressValidationCache.shared.address(address, kind: kind, networkMode: networkMode).normalizedValue
    }
    nonisolated static func isValidAptosTokenType(_ value: String) -> Bool {
        AddressValidationCache.shared.string(value, kind: "aptosTokenType").isValid
    }
}
