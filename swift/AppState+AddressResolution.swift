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


/// What differs between chains when resolving an address.
///
/// The key path to the wallet's stored address and the validation kind used to
/// be columns here too, and both were the row's own key: the address is
/// `wallet.address(forChainNamed:)` and the kind is
/// `Chain.addressValidationKind`, which the registry has answered since the
/// identity table landed. What is left is three flags that genuinely vary.
private struct ChainAddressDescriptor {
    let chain: Chain
    /// Whether this chain derives from the wallet's configured seed path
    /// rather than from `walletDerivationPath(for:chain:)`. Used to be a
    /// `KeyPath` into a per-chain field on `SeedDerivationPaths`; the paths are
    /// a map now, so the chain itself is the key and only the opt-in remains.
    let usesConfiguredSeedPath: Bool
    let derivedPostProcess: DerivedAddressPostProcess
    let normalizeStored: Bool
    init(
        _ chain: Chain,
        usesConfiguredSeedPath: Bool = false,
        post: DerivedAddressPostProcess = .none, normalize: Bool = false
    ) {
        self.chain = chain
        self.usesConfiguredSeedPath = usesConfiguredSeedPath
        self.derivedPostProcess = post; self.normalizeStored = normalize
    }
}

@MainActor
extension AppState {

    func resolvedEthereumAddress(for wallet: ImportedWallet) -> String? { resolvedEVMAddress(for: wallet, chainName: "Ethereum") }

    func resolvedEVMAddress(for wallet: ImportedWallet, chainName: String) -> String? {
        guard isEVMChain(chainName), EVMChainContext(chainName: chainName) != nil else { return nil }
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

    /// The address for a chain that has a testnet the app can switch to, so the
    /// derivation chain depends on the wallet's network mode rather than on the
    /// name alone.
    ///
    /// Bitcoin and Dogecoin were separate copies of this. Dogecoin's built its
    /// path from a hand-written `m/44'/3'/…` helper — the same path the
    /// registry already carries, but assembled by hand, so it read the wallet's
    /// derivation *account* and then discarded the rest of the resolution: a
    /// custom Dogecoin path was honoured everywhere except when resolving the
    /// address it produced.
    func resolvedNetworkModeAddress(
        for wallet: ImportedWallet,
        family: String,
        fallback: Chain
    ) -> String? {
        let chainID = walletNetworkChainID(for: wallet, family: family)
        let chain = seedDerivationChain(forChainID: chainID) ?? fallback
        return resolveDerivedOrStoredAddress(
            for: wallet, chain: chain,
            derivationPath: walletDerivationPath(for: wallet, chain: chain),
            storedAddress: wallet.address(forChainNamed: fallback.displayName),
            validationKind: (Chain(id: chainID)?.addressValidationKind ?? "")
        )
    }

    private static let addressDescriptors: [Chain: ChainAddressDescriptor] = {
        let all: [ChainAddressDescriptor] = [
            .init(.tron, usesConfiguredSeedPath: true),
            .init(.solana),
            .init(.sui, normalize: true),
            .init(.aptos, normalize: true),
            .init(.ton, normalize: true),
            .init(.icp, usesConfiguredSeedPath: true, normalize: true),
            .init(.near, post: .lowercase, normalize: true),
            .init(.polkadot, usesConfiguredSeedPath: true, post: .trim),
            .init(.zcash, usesConfiguredSeedPath: true),
            .init(.bitcoinGold, usesConfiguredSeedPath: true),
            .init(.decred, usesConfiguredSeedPath: true),
            .init(.kaspa, usesConfiguredSeedPath: true, post: .lowercase, normalize: true),
            .init(.dash, usesConfiguredSeedPath: true),
            .init(.bittensor, usesConfiguredSeedPath: true, post: .trim),
            .init(.stellar, usesConfiguredSeedPath: true, post: .trim),
            .init(.xrp),
            .init(.litecoin),
            .init(.bitcoinCash),
            .init(.bitcoinSv),
        ]
        return Dictionary(uniqueKeysWithValues: all.map { ($0.chain, $0) })
    }()

    func resolvedChainAddress(for wallet: ImportedWallet, chain: Chain) -> String? {
        guard let desc = Self.addressDescriptors[chain] else { return nil }
        let derivationPath =
            desc.usesConfiguredSeedPath
            ? wallet.seedDerivationPaths.path(for: chain)
            : walletDerivationPath(for: wallet, chain: chain)
        return resolveDerivedOrStoredAddress(
            for: wallet, chain: chain, derivationPath: derivationPath,
            storedAddress: wallet.address(forChainNamed: chain.displayName),
            validationKind: chain.addressValidationKind,
            derivedPostProcess: desc.derivedPostProcess,
            normalizeStored: desc.normalizeStored
        )
    }

    func resolvedTronAddress(for wallet: ImportedWallet) -> String?       { resolvedChainAddress(for: wallet, chain: .tron) }
    func resolvedSolanaAddress(for wallet: ImportedWallet) -> String?     { resolvedChainAddress(for: wallet, chain: .solana) }
    func resolvedSuiAddress(for wallet: ImportedWallet) -> String?        { resolvedChainAddress(for: wallet, chain: .sui) }
    func resolvedAptosAddress(for wallet: ImportedWallet) -> String?      { resolvedChainAddress(for: wallet, chain: .aptos) }
    func resolvedTONAddress(for wallet: ImportedWallet) -> String?        { resolvedChainAddress(for: wallet, chain: .ton) }
    func resolvedICPAddress(for wallet: ImportedWallet) -> String?        { resolvedChainAddress(for: wallet, chain: .icp) }
    func resolvedNearAddress(for wallet: ImportedWallet) -> String?       { resolvedChainAddress(for: wallet, chain: .near) }
    func resolvedPolkadotAddress(for wallet: ImportedWallet) -> String?   { resolvedChainAddress(for: wallet, chain: .polkadot) }
    func resolvedStellarAddress(for wallet: ImportedWallet) -> String?    { resolvedChainAddress(for: wallet, chain: .stellar) }
    func resolvedXRPAddress(for wallet: ImportedWallet) -> String?        { resolvedChainAddress(for: wallet, chain: .xrp) }
    func resolvedLitecoinAddress(for wallet: ImportedWallet) -> String?   { resolvedChainAddress(for: wallet, chain: .litecoin) }
    func resolvedBitcoinCashAddress(for wallet: ImportedWallet) -> String?{ resolvedChainAddress(for: wallet, chain: .bitcoinCash) }
    func resolvedBitcoinSVAddress(for wallet: ImportedWallet) -> String?  { resolvedChainAddress(for: wallet, chain: .bitcoinSv) }

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

    func resolvedMoneroAddress(for wallet: ImportedWallet) -> String? {
        guard let addr = wallet.moneroAddress, AddressValidation.isValid(addr, kind: "monero") else { return nil }
        return addr.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func resolvedAddress(for wallet: ImportedWallet, chainName: String) -> String? {
        // These four do not resolve like the rest and must stay explicit:
        // Bitcoin and Dogecoin pick their derivation chain from the selected
        // network mode, Cardano tries the stored address before deriving, and
        // Monero only ever uses a stored address — routing it through the
        // generic path would make it attempt a derivation it has no key for.
        switch chainName {
        case "Bitcoin": return resolvedNetworkModeAddress(for: wallet, family: "bitcoin", fallback: .bitcoin)
        case "Dogecoin": return resolvedNetworkModeAddress(for: wallet, family: "dogecoin", fallback: .dogecoin)
        case "Cardano": return resolvedCardanoAddress(for: wallet)
        case "Monero": return resolvedMoneroAddress(for: wallet)
        default: break
        }
        // Everything else is the same lookup with a different slot, and the
        // chain-name → derivation-chain mapping already comes from core.
        if let chain = seedDerivationChain(for: chainName) {
            return resolvedChainAddress(for: wallet, chain: chain)
        }
        if isEVMChain(chainName) { return resolvedEVMAddress(for: wallet, chainName: chainName) }
        return nil
    }


    private func resolveDerivedOrStoredAddress(
        for wallet: ImportedWallet,
        chain: Chain,
        derivationPath: String,
        storedAddress: String?,
        validationKind: String,
        derivedPostProcess: DerivedAddressPostProcess = .none,
        normalizeStored: Bool = false
    ) -> String? {
        let derived: String? = {
            guard let seedPhrase = storedSeedPhrase(for: wallet.id) else { return nil }
            return try? WalletDerivationLayer.deriveAddress(
                seedPhrase: seedPhrase, chain: chain, derivationPath: derivationPath
            )
        }()
        return coreResolveDerivedOrStoredAddress(
            derived: derived, stored: storedAddress, validationKind: validationKind,
            derivedPostProcess: derivedPostProcess,
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
private final class AddressValidationCache: @unchecked Sendable {
    static let shared = AddressValidationCache()
    private let lock = NSLock()
    /// One cache. There were two, of the same type, keyed the same way, because
    /// core had two exports and two identical record pairs for "is this typed
    /// string well formed, and how is it spelled".
    private var addressCache: [String: AddressValidationResult] = [:]
    private static let maxEntries = 512
    private init() {}
    func address(_ address: String, kind: String) -> AddressValidationResult {
        let key = "\(kind)|\(address)"
        lock.lock()
        if let cached = addressCache[key] { lock.unlock(); return cached }
        lock.unlock()
        let result = coreValidateAddress(request: AddressValidationRequest(kind: kind, value: address))
        lock.lock()
        defer { lock.unlock() }
        if addressCache.count > Self.maxEntries {
            addressCache.removeAll(keepingCapacity: true)
        }
        addressCache[key] = result
        return result
    }
}

enum AddressValidation {
    static func isValid(_ address: String, kind: String) -> Bool {
        AddressValidationCache.shared.address(address, kind: kind).isValid
    }
    static func normalized(_ address: String, kind: String) -> String? {
        AddressValidationCache.shared.address(address, kind: kind).normalizedValue
    }
    static func isValidAptosTokenType(_ value: String) -> Bool {
        AddressValidationCache.shared.address(value, kind: "aptosTokenType").isValid
    }
}
