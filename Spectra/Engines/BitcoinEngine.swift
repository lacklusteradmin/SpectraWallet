import Foundation
import BitcoinDevKit

enum BitcoinNetworkMode: String, CaseIterable, Identifiable {
    case mainnet
    case testnet
    case testnet4
    case signet

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mainnet:
            return "Mainnet"
        case .testnet:
            return "Testnet"
        case .testnet4:
            return "Testnet4"
        case .signet:
            return "Signet"
        }
    }

    var bdkNetwork: Network {
        switch self {
        case .mainnet:
            return .bitcoin
        case .testnet:
            return .testnet
        case .testnet4:
            return .testnet
        case .signet:
            return .signet
        }
    }
}

enum BitcoinFeePriority: String, CaseIterable, Identifiable {
    case economy
    case normal
    case priority

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .economy:
            return "Economy"
        case .normal:
            return "Normal"
        case .priority:
            return "Priority"
        }
    }
}

struct BitcoinSendPreview: Equatable {
    let estimatedFeeRateSatVb: UInt64
    let estimatedNetworkFeeBTC: Double
    let feeRateDescription: String?
    let spendableBalance: Double?
    let estimatedTransactionBytes: Int?
    let selectedInputCount: Int?
    let usesChangeOutput: Bool?
    let maxSendable: Double?
}

struct BitcoinSendResult: Equatable {
    let transactionHash: String
    let rawTransactionHex: String
    let verificationStatus: SendBroadcastVerificationStatus
}

struct BitcoinWalletEngine {
    private static let dustThresholdSats: UInt64 = 546
    private static let minimumFeeRateSatVb: UInt64 = 1
    private static let maxStandardTransactionBytes: UInt64 = 100_000
    private static let endpointReliabilityDefaultsKey = "bitcoin.engine.endpoint.reliability.v1"

    private struct EndpointReliabilityCounter: Codable {
        var successCount: Int
        var failureCount: Int
        var lastUpdatedAt: TimeInterval
    }

    private enum ScriptDescriptorKind {
        case legacy
        case nestedSegWit
        case nativeSegWit
        case taproot

        func descriptorString(for keyExpression: String) -> String {
            switch self {
            case .legacy:
                return "pkh(\(keyExpression))"
            case .nestedSegWit:
                return "sh(wpkh(\(keyExpression)))"
            case .nativeSegWit:
                return "wpkh(\(keyExpression))"
            case .taproot:
                return "tr(\(keyExpression))"
            }
        }
    }

    private static var networkMode: BitcoinNetworkMode = .mainnet
    private static var customEsploraEndpoints: [String] = []
    private static var stopGap: UInt64 = 10
    private static let parallelRequests: UInt64 = 4
    static let validMnemonicWordCounts = [12, 15, 18, 21, 24]

    struct Session {
        let wallet: Wallet
        let persister: Persister
    }

    static func configureRuntime(
        networkMode: BitcoinNetworkMode,
        esploraEndpoints: [String],
        stopGap: Int
    ) {
        self.networkMode = networkMode
        customEsploraEndpoints = esploraEndpoints
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.stopGap = UInt64(max(1, min(stopGap, 200)))
    }

    static func isValidAddress(_ address: String, networkMode: BitcoinNetworkMode) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        func canParse(on network: Network) -> Bool {
            (try? Address(address: trimmed, network: network)) != nil
        }

        switch networkMode {
        case .mainnet:
            return canParse(on: .bitcoin)
        case .testnet:
            return canParse(on: .testnet)
        case .testnet4:
            return canParse(on: .testnet)
        case .signet:
            return canParse(on: .signet)
        }
    }

    static func isLikelyExtendedPublicKey(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["xpub", "ypub", "zpub", "tpub", "upub", "vpub"]
        return prefixes.contains(where: { trimmed.lowercased().hasPrefix($0) }) && trimmed.count > 100
    }

    static func normalizedMnemonicWords(from seedPhrase: String) -> [String] {
        seedPhrase
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    static func normalizedMnemonicPhrase(from seedPhrase: String) -> String {
        normalizedMnemonicWords(from: seedPhrase).joined(separator: " ")
    }

    static func invalidEnglishWords(in seedPhrase: String) -> [String] {
        var seen: Set<String> = []
        return normalizedMnemonicWords(from: seedPhrase).reduce(into: [String]()) { result, word in
            guard !BIP39EnglishWordList.words.contains(word) else { return }
            guard seen.insert(word).inserted else { return }
            result.append(word)
        }
    }

    static func validateMnemonic(_ seedPhrase: String, expectedWordCount: Int? = nil) -> String? {
        let trimmedPhrase = seedPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPhrase.isEmpty else {
            return "Enter a BIP-39 seed phrase."
        }

        let words = normalizedMnemonicWords(from: trimmedPhrase)
        let normalizedPhrase = words.joined(separator: " ")

        if let expectedWordCount, words.count != expectedWordCount {
            return "This seed phrase has \(words.count) words. Selected length is \(expectedWordCount)."
        }

        guard validMnemonicWordCounts.contains(words.count) else {
            return "Use a valid BIP-39 seed phrase with 12, 15, 18, 21, or 24 words."
        }

        let invalidWords = invalidEnglishWords(in: normalizedPhrase)
        guard invalidWords.isEmpty else {
            let joinedWords = invalidWords.joined(separator: ", ")
            return "These words are not in the BIP-39 English word list: \(joinedWords)."
        }

        do {
            _ = try Mnemonic.fromString(mnemonic: normalizedPhrase)
            return nil
        } catch {
            return "This seed phrase is not a valid BIP-39 mnemonic. Check the word spelling and checksum."
        }
    }

    static func hasValidMnemonicChecksum(_ seedPhrase: String, expectedWordCount: Int? = nil) -> Bool {
        validateMnemonic(seedPhrase, expectedWordCount: expectedWordCount) == nil
    }

    static func generateMnemonic(wordCount: Int) throws -> String {
        let targetWordCount = validMnemonicWordCounts.contains(wordCount) ? wordCount : 12
        let mnemonicWordCount: WordCount
        switch targetWordCount {
        case 12:
            mnemonicWordCount = .words12
        case 15:
            mnemonicWordCount = .words15
        case 18:
            mnemonicWordCount = .words18
        case 21:
            mnemonicWordCount = .words21
        case 24:
            mnemonicWordCount = .words24
        default:
            mnemonicWordCount = .words12
        }
        let mnemonic = Mnemonic(wordCount: mnemonicWordCount)
        return normalizedMnemonicPhrase(from: String(describing: mnemonic))
    }

    static func syncBalance(for importedWallet: ImportedWallet, seedPhrase: String) throws -> Double {
        let session = try makeSession(for: importedWallet, seedPhrase: seedPhrase)
        try sync(session: session)
        return session.wallet.balance().total.toBtc()
    }

    static func syncBalance(for walletID: UUID, seedPhrase: String) throws -> Double {
        let session = try makeSession(
            for: walletID,
            seedPhrase: seedPhrase,
            derivationPath: SeedDerivationChain.bitcoin.defaultPath
        )
        try sync(session: session)
        return session.wallet.balance().total.toBtc()
    }

    static func syncBalanceInBackground(for importedWallet: ImportedWallet, seedPhrase: String) async throws -> Double {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let balance = try syncBalance(for: importedWallet, seedPhrase: seedPhrase)
                    continuation.resume(returning: balance)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func syncBalanceInBackground(for walletID: UUID, seedPhrase: String) async throws -> Double {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let balance = try syncBalance(for: walletID, seedPhrase: seedPhrase)
                    continuation.resume(returning: balance)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func nextReceiveAddress(for importedWallet: ImportedWallet, seedPhrase: String) throws -> String {
        let session = try makeSession(for: importedWallet, seedPhrase: seedPhrase)
        let nextIndex = session.wallet.nextDerivationIndex(keychain: .external)
        let addressInfo = session.wallet.peekAddress(keychain: .external, index: nextIndex)
        return String(describing: addressInfo.address)
    }

    static func nextReceiveAddress(for walletID: UUID, seedPhrase: String) throws -> String {
        try nextReceiveAddress(
            for: walletID,
            seedPhrase: seedPhrase,
            derivationPath: SeedDerivationChain.bitcoin.defaultPath
        )
    }

    static func nextReceiveAddress(
        for walletID: UUID,
        seedPhrase: String,
        derivationPath: String
    ) throws -> String {
        let session = try makeSession(for: walletID, seedPhrase: seedPhrase, derivationPath: derivationPath)
        let nextIndex = session.wallet.nextDerivationIndex(keychain: .external)
        let addressInfo = session.wallet.peekAddress(keychain: .external, index: nextIndex)
        return String(describing: addressInfo.address)
    }

    static func derivedAddress(
        for walletID: UUID,
        seedPhrase: String,
        derivationPath: String = SeedDerivationChain.bitcoin.defaultPath
    ) throws -> String {
        let session = try makeSession(for: walletID, seedPhrase: seedPhrase, derivationPath: derivationPath)
        let addressInfo = session.wallet.peekAddress(keychain: .external, index: 0)
        return String(describing: addressInfo.address)
    }

    static func nextReceiveAddressInBackground(for importedWallet: ImportedWallet, seedPhrase: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let address = try nextReceiveAddress(for: importedWallet, seedPhrase: seedPhrase)
                    continuation.resume(returning: address)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func nextReceiveAddressInBackground(for walletID: UUID, seedPhrase: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let address = try nextReceiveAddress(for: walletID, seedPhrase: seedPhrase)
                    continuation.resume(returning: address)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func addressInventory(
        for importedWallet: ImportedWallet,
        seedPhrase: String,
        scanLimit: UInt32 = 20
    ) throws -> WalletAddressInventory {
        let session = try makeSession(for: importedWallet, seedPhrase: seedPhrase)
        return addressInventory(
            session: session,
            derivationPath: importedWallet.seedDerivationPaths.bitcoin,
            scanLimit: scanLimit
        )
    }

    static func addressInventory(
        for walletID: UUID,
        seedPhrase: String,
        derivationPath: String = SeedDerivationChain.bitcoin.defaultPath,
        scanLimit: UInt32 = 20
    ) throws -> WalletAddressInventory {
        let session = try makeSession(for: walletID, seedPhrase: seedPhrase, derivationPath: derivationPath)
        return addressInventory(
            session: session,
            derivationPath: derivationPath,
            scanLimit: scanLimit
        )
    }

    @discardableResult
    static func send(from importedWallet: ImportedWallet, seedPhrase: String, to recipientAddress: String, amountBTC: Double) throws -> String {
        try send(
            from: importedWallet,
            seedPhrase: seedPhrase,
            to: recipientAddress,
            amountBTC: amountBTC,
            feePriority: .normal
        ).transactionHash
    }

    static func send(from walletID: UUID, seedPhrase: String, to recipientAddress: String, amountBTC: Double) throws -> String {
        try send(
            from: walletID,
            seedPhrase: seedPhrase,
            to: recipientAddress,
            amountBTC: amountBTC,
            feePriority: .normal
        ).transactionHash
    }

    static func send(
        from importedWallet: ImportedWallet,
        seedPhrase: String,
        to recipientAddress: String,
        amountBTC: Double,
        feePriority: BitcoinFeePriority,
        providerIDs: Set<String>? = nil
    ) throws -> (transactionHash: String, rawTransactionHex: String) {
        let session = try makeSession(for: importedWallet, seedPhrase: seedPhrase)
        try sync(session: session)

        let recipient = try Address(address: recipientAddress, network: currentNetwork())
        let amount = try Amount.fromBtc(btc: amountBTC)
        let sendAmountSats = UInt64((amountBTC * 100_000_000).rounded())

        let feeEstimates = try performWithClientFallback { client in
            try client.getFeeEstimates()
        }
        let estimatedRate = feeEstimate(for: feePriority, from: feeEstimates)
        let satPerVb = max(UInt64(1), UInt64(ceil(estimatedRate)))
        try validatePolicyRules(sendAmountSats: sendAmountSats, estimatedVBytes: estimatedVirtualBytes(for: importedWallet.seedDerivationPaths.bitcoin))
        let feeRate = try FeeRate.fromSatPerVb(satVb: satPerVb)

        let psbt = try TxBuilder()
            .addRecipient(script: recipient.scriptPubkey(), amount: amount)
            .feeRate(feeRate: feeRate)
            .finish(wallet: session.wallet)

        let finalized = try session.wallet.sign(psbt: psbt, signOptions: nil)
        guard finalized else {
            throw BitcoinWalletEngineError.signingFailed
        }

        let transaction = try psbt.extractTx()
        let txid = String(describing: transaction.computeTxid())
        let rawTransactionHex = transaction.serialize().map { String(format: "%02x", $0) }.joined()
        try broadcastWithRecovery(transaction: transaction, txid: txid, providerIDs: providerIDs)
        _ = try session.wallet.persist(persister: session.persister)
        try sync(session: session)

        return (txid, rawTransactionHex)
    }

    static func send(
        from walletID: UUID,
        seedPhrase: String,
        to recipientAddress: String,
        amountBTC: Double,
        feePriority: BitcoinFeePriority,
        providerIDs: Set<String>? = nil
    ) throws -> (transactionHash: String, rawTransactionHex: String) {
        let session = try makeSession(for: walletID, seedPhrase: seedPhrase)
        try sync(session: session)

        let recipient = try Address(address: recipientAddress, network: currentNetwork())
        let amount = try Amount.fromBtc(btc: amountBTC)
        let sendAmountSats = UInt64((amountBTC * 100_000_000).rounded())

        let feeEstimates = try performWithClientFallback { client in
            try client.getFeeEstimates()
        }
        let estimatedRate = feeEstimate(for: feePriority, from: feeEstimates)
        let satPerVb = max(UInt64(1), UInt64(ceil(estimatedRate)))
        try validatePolicyRules(sendAmountSats: sendAmountSats, estimatedVBytes: estimatedVirtualBytes(for: SeedDerivationChain.bitcoin.defaultPath))
        let feeRate = try FeeRate.fromSatPerVb(satVb: satPerVb)

        let psbt = try TxBuilder()
            .addRecipient(script: recipient.scriptPubkey(), amount: amount)
            .feeRate(feeRate: feeRate)
            .finish(wallet: session.wallet)

        let finalized = try session.wallet.sign(psbt: psbt, signOptions: nil)
        guard finalized else {
            throw BitcoinWalletEngineError.signingFailed
        }

        let transaction = try psbt.extractTx()
        let txid = String(describing: transaction.computeTxid())
        let rawTransactionHex = transaction.serialize().map { String(format: "%02x", $0) }.joined()
        try broadcastWithRecovery(transaction: transaction, txid: txid, providerIDs: providerIDs)
        _ = try session.wallet.persist(persister: session.persister)
        try sync(session: session)

        return (txid, rawTransactionHex)
    }

    @discardableResult
    static func sendInBackground(from importedWallet: ImportedWallet, seedPhrase: String, to recipientAddress: String, amountBTC: Double) async throws -> BitcoinSendResult {
        try await sendInBackground(
            from: importedWallet,
            seedPhrase: seedPhrase,
            to: recipientAddress,
            amountBTC: amountBTC,
            feePriority: .normal
        )
    }

    @discardableResult
    static func sendInBackground(
        from importedWallet: ImportedWallet,
        seedPhrase: String,
        to recipientAddress: String,
        amountBTC: Double,
        feePriority: BitcoinFeePriority,
        providerIDs: Set<String>? = nil
    ) async throws -> BitcoinSendResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let sent = try send(
                        from: importedWallet,
                        seedPhrase: seedPhrase,
                        to: recipientAddress,
                        amountBTC: amountBTC,
                        feePriority: feePriority,
                        providerIDs: providerIDs
                    )
                    continuation.resume(returning: BitcoinSendResult(
                        transactionHash: sent.transactionHash,
                        rawTransactionHex: sent.rawTransactionHex,
                        verificationStatus: verifyBroadcastedTransactionIfAvailable(txid: sent.transactionHash, providerIDs: providerIDs)
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func sendInBackground(
        from walletID: UUID,
        seedPhrase: String,
        to recipientAddress: String,
        amountBTC: Double,
        feePriority: BitcoinFeePriority = .normal,
        providerIDs: Set<String>? = nil
    ) async throws -> BitcoinSendResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let sent = try send(
                        from: walletID,
                        seedPhrase: seedPhrase,
                        to: recipientAddress,
                        amountBTC: amountBTC,
                        feePriority: feePriority,
                        providerIDs: providerIDs
                    )
                    continuation.resume(returning: BitcoinSendResult(
                        transactionHash: sent.transactionHash,
                        rawTransactionHex: sent.rawTransactionHex,
                        verificationStatus: verifyBroadcastedTransactionIfAvailable(txid: sent.transactionHash, providerIDs: providerIDs)
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func estimateSendPreview(
        for importedWallet: ImportedWallet,
        seedPhrase: String,
        feePriority: BitcoinFeePriority
    ) throws -> BitcoinSendPreview {
        let session = try makeSession(for: importedWallet, seedPhrase: seedPhrase)
        try sync(session: session)
        let feeEstimates = try performWithClientFallback { client in
            try client.getFeeEstimates()
        }
        let rate = feeEstimate(for: feePriority, from: feeEstimates)
        let satPerVb = max(UInt64(1), UInt64(ceil(rate)))

        let estimatedVBytes: UInt64 = estimatedVirtualBytes(for: importedWallet.seedDerivationPaths.bitcoin)
        let estimatedSats = satPerVb * estimatedVBytes
        let estimatedFeeBTC = Double(estimatedSats) / 100_000_000
        return BitcoinSendPreview(
            estimatedFeeRateSatVb: satPerVb,
            estimatedNetworkFeeBTC: estimatedFeeBTC,
            feeRateDescription: "\(satPerVb) sat/vB",
            spendableBalance: nil,
            estimatedTransactionBytes: Int(estimatedVBytes),
            selectedInputCount: nil,
            usesChangeOutput: nil,
            maxSendable: nil
        )
    }

    static func estimateSendPreview(
        for walletID: UUID,
        seedPhrase: String,
        feePriority: BitcoinFeePriority
    ) throws -> BitcoinSendPreview {
        let session = try makeSession(for: walletID, seedPhrase: seedPhrase)
        try sync(session: session)
        let feeEstimates = try performWithClientFallback { client in
            try client.getFeeEstimates()
        }
        let rate = feeEstimate(for: feePriority, from: feeEstimates)
        let satPerVb = max(UInt64(1), UInt64(ceil(rate)))

        let estimatedVBytes: UInt64 = estimatedVirtualBytes(for: SeedDerivationChain.bitcoin.defaultPath)
        let estimatedSats = satPerVb * estimatedVBytes
        let estimatedFeeBTC = Double(estimatedSats) / 100_000_000
        return BitcoinSendPreview(
            estimatedFeeRateSatVb: satPerVb,
            estimatedNetworkFeeBTC: estimatedFeeBTC,
            feeRateDescription: "\(satPerVb) sat/vB",
            spendableBalance: nil,
            estimatedTransactionBytes: Int(estimatedVBytes),
            selectedInputCount: nil,
            usesChangeOutput: nil,
            maxSendable: nil
        )
    }

    private static func makeSession(for importedWallet: ImportedWallet, seedPhrase: String) throws -> Session {
        try makeSession(
            for: importedWallet.id,
            seedPhrase: seedPhrase,
            derivationPath: importedWallet.seedDerivationPaths.bitcoin
        )
    }

    private static func makeSession(for walletID: UUID, seedPhrase: String) throws -> Session {
        try makeSession(
            for: walletID,
            seedPhrase: seedPhrase,
            derivationPath: SeedDerivationChain.bitcoin.defaultPath
        )
    }

    private static func makeSession(
        for walletID: UUID,
        seedPhrase: String,
        derivationPath: String
    ) throws -> Session {
        let mnemonic = try Mnemonic.fromString(mnemonic: seedPhrase)
        let network = currentNetwork()
        let secretKey = DescriptorSecretKey(network: network, mnemonic: mnemonic, password: nil)
        let descriptors = try descriptors(for: secretKey, derivationPath: derivationPath, network: network)
        let persister = try Persister.newSqlite(path: databasePath(for: walletID))

        let wallet: Wallet
        do {
            wallet = try Wallet.load(
                descriptor: descriptors.receive,
                changeDescriptor: descriptors.change,
                persister: persister,
                lookahead: UInt32(stopGap)
            )
        } catch {
            wallet = try Wallet(
                descriptor: descriptors.receive,
                changeDescriptor: descriptors.change,
                network: network,
                persister: persister,
                lookahead: UInt32(stopGap)
            )
        }

        return Session(wallet: wallet, persister: persister)
    }

    private static func sync(session: Session) throws {
        let request = try session.wallet.startFullScan().build()
        let update = try performWithClientFallback { client in
            try client.fullScan(
                request: request,
                stopGap: stopGap,
                parallelRequests: parallelRequests
            )
        }
        try session.wallet.applyUpdate(update: update)
        _ = try session.wallet.persist(persister: session.persister)
    }

    private static func databasePath(for walletID: UUID) -> String {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = baseDirectory.appendingPathComponent("SpectraBitcoin", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(walletID.uuidString).sqlite").path
    }

    private static func feeEstimate(for priority: BitcoinFeePriority, from estimates: [UInt16: Double]) -> Double {
        let deterministicFallback: Double
        switch priority {
        case .economy:
            deterministicFallback = 2.0
        case .normal:
            deterministicFallback = 5.0
        case .priority:
            deterministicFallback = 10.0
        }

        func firstValid(_ targets: [UInt16]) -> Double? {
            for target in targets {
                if let estimate = estimates[target], estimate > 0 {
                    return estimate
                }
            }
            return nil
        }

        switch priority {
        case .economy:
            return firstValid([12, 10, 8, 6, 4, 3, 2]) ?? deterministicFallback
        case .normal:
            return firstValid([6, 5, 4, 3, 8, 10, 12, 2]) ?? deterministicFallback
        case .priority:
            return firstValid([2, 1, 3, 4, 5, 6]) ?? deterministicFallback
        }
    }

    private static func currentNetwork() -> Network {
        networkMode.bdkNetwork
    }

    private static func descriptors(
        for rootKey: DescriptorSecretKey,
        derivationPath rawDerivationPath: String,
        network: Network
    ) throws -> (receive: Descriptor, change: Descriptor) {
        let derivationPath = DerivationPathParser.normalize(
            rawDerivationPath,
            fallback: SeedDerivationChain.bitcoin.defaultPath
        )
        guard let segments = DerivationPathParser.parse(derivationPath) else {
            throw BitcoinWalletEngineError.unsupportedDerivationPath(derivationPath)
        }

        let descriptorKind: ScriptDescriptorKind
        let accountSegments: [DerivationPathSegment]
        if ((segments.count == 2 &&
             segments[1].value == 0 &&
             !segments[1].isHardened) ||
            (segments.count == 3 &&
             segments[1].value == 0 &&
             !segments[1].isHardened &&
             segments[2].value == 0 &&
             !segments[2].isHardened)),
           segments[0].value == 0,
           segments[0].isHardened {
            descriptorKind = .legacy
            accountSegments = [segments[0]]
        } else {
            guard segments.count >= 5,
                  segments[1].value == 0,
                  segments[0].isHardened,
                  segments[1].isHardened,
                  segments[2].isHardened else {
                throw BitcoinWalletEngineError.unsupportedDerivationPath(derivationPath)
            }

            switch segments[0].value {
            case 44:
                descriptorKind = .legacy
            case 49:
                descriptorKind = .nestedSegWit
            case 84:
                descriptorKind = .nativeSegWit
            case 86:
                descriptorKind = .taproot
            default:
                throw BitcoinWalletEngineError.unsupportedDerivationPath(derivationPath)
            }

            accountSegments = Array(segments.prefix(3))
        }

        let accountPath = DerivationPathParser.string(from: accountSegments)
        let accountKey = try rootKey.derive(path: DerivationPath(path: accountPath))
        let accountKeyString = String(describing: accountKey)
        let receiveDescriptor = try Descriptor(
            descriptor: descriptorKind.descriptorString(for: "\(accountKeyString)/0/*"),
            network: network
        )
        let changeDescriptor = try Descriptor(
            descriptor: descriptorKind.descriptorString(for: "\(accountKeyString)/1/*"),
            network: network
        )
        return (receiveDescriptor, changeDescriptor)
    }

    private static func estimatedVirtualBytes(for derivationPath: String) -> UInt64 {
        let normalized = DerivationPathParser.normalize(
            derivationPath,
            fallback: SeedDerivationChain.bitcoin.defaultPath
        )
        switch normalized {
        case let path where path.hasPrefix("m/44'"):
            return 260
        case let path where path.hasPrefix("m/49'"):
            return 250
        case let path where path.hasPrefix("m/86'"):
            return 205
        case "m/0'/0", "m/0'/0/0":
            return 260
        default:
            return 225
        }
    }

    private static func addressInventory(
        session: Session,
        derivationPath: String,
        scanLimit: UInt32
    ) -> WalletAddressInventory {
        let normalizedPath = DerivationPathParser.normalize(
            derivationPath,
            fallback: SeedDerivationChain.bitcoin.defaultPath
        )
        let account = DerivationPathParser.segmentValue(at: 2, in: normalizedPath) ?? 0
        var entries: [WalletAddressInventoryEntry] = []

        for index in 0 ..< scanLimit {
            let externalAddress = String(describing: session.wallet.peekAddress(keychain: .external, index: index).address)
            entries.append(
                WalletAddressInventoryEntry(
                    address: externalAddress,
                    derivationPath: DerivationPathParser.replacingLastTwoSegments(
                        in: normalizedPath,
                        branch: 0,
                        index: index,
                        fallback: normalizedPath
                    ),
                    account: account,
                    branchIndex: 0,
                    addressIndex: index,
                    role: index == 0 ? .primary : .external
                )
            )

            let changeAddress = String(describing: session.wallet.peekAddress(keychain: .internal, index: index).address)
            entries.append(
                WalletAddressInventoryEntry(
                    address: changeAddress,
                    derivationPath: DerivationPathParser.replacingLastTwoSegments(
                        in: normalizedPath,
                        branch: 1,
                        index: index,
                        fallback: normalizedPath
                    ),
                    account: account,
                    branchIndex: 1,
                    addressIndex: index,
                    role: .change
                )
            )
        }

        return WalletAddressInventory(
            entries: entries,
            supportsDiscoveryScan: true,
            supportsChangeBranch: true,
            scanLimit: scanLimit
        )
    }

    private static func validatePolicyRules(sendAmountSats: UInt64, estimatedVBytes: UInt64) throws {
        guard sendAmountSats >= dustThresholdSats else {
            throw BitcoinWalletEngineError.policyViolation("Amount is below Bitcoin dust threshold.")
        }
        guard minimumFeeRateSatVb > 0 else {
            throw BitcoinWalletEngineError.policyViolation("Bitcoin fee-rate policy is misconfigured.")
        }
        guard estimatedVBytes <= maxStandardTransactionBytes else {
            throw BitcoinWalletEngineError.policyViolation("Bitcoin transaction is too large for standard relay policy.")
        }
    }

    private static func defaultEsploraEndpoints(for mode: BitcoinNetworkMode) -> [String] {
        ChainBackendRegistry.BitcoinRuntimeEndpoints.esploraBaseURLs(for: mode)
    }

    private static func resolvedEsploraEndpoints() -> [String] {
        if !customEsploraEndpoints.isEmpty {
            return customEsploraEndpoints
        }
        return defaultEsploraEndpoints(for: networkMode)
    }

    static func endpointCatalog(for mode: BitcoinNetworkMode, custom: [String] = []) -> [String] {
        if !custom.isEmpty {
            return custom
        }
        return defaultEsploraEndpoints(for: mode)
    }

    private static func performWithClientFallback<T>(
        providerIDs: Set<String>? = nil,
        _ operation: (EsploraClient) throws -> T
    ) throws -> T {
        var lastError: Error?
        for endpoint in orderedEsploraEndpoints() {
            let client = EsploraClient(url: endpoint)
            do {
                let value = try operation(client)
                recordEndpointAttempt(endpoint: endpoint, success: true)
                return value
            } catch {
                lastError = error
                recordEndpointAttempt(endpoint: endpoint, success: false)
                continue
            }
        }
        throw lastError ?? URLError(.cannotConnectToHost)
    }

    static func rebroadcastSignedTransactionInBackground(
        rawTransactionHex: String,
        expectedTransactionHash: String? = nil,
        providerIDs: Set<String>? = nil
    ) async throws -> BitcoinSendResult {
        let fallbackTransactionHash = expectedTransactionHash?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? expectedTransactionHash!.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let transactionHash = try await broadcastRawTransactionHex(
            rawTransactionHex,
            fallbackTransactionHash: fallbackTransactionHash,
            providerIDs: providerIDs
        )
        return BitcoinSendResult(
            transactionHash: transactionHash,
            rawTransactionHex: rawTransactionHex,
            verificationStatus: verifyBroadcastedTransactionIfAvailable(txid: transactionHash, providerIDs: providerIDs)
        )
    }

    private static func broadcastRawTransactionHex(
        _ rawTransactionHex: String,
        fallbackTransactionHash: String,
        providerIDs: Set<String>? = nil
    ) async throws -> String {
        let trimmedRawHex = rawTransactionHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRawHex.isEmpty,
              let rawTransactionData = Data(hexEncoded: trimmedRawHex),
              !rawTransactionData.isEmpty else {
            throw BitcoinWalletEngineError.signingFailed
        }
        guard UInt64(rawTransactionData.count) <= maxStandardTransactionBytes else {
            throw BitcoinWalletEngineError.policyViolation("Bitcoin transaction is too large for standard relay policy.")
        }

        var lastError: Error?
        for endpoint in orderedEsploraEndpoints(providerIDs: providerIDs) {
            guard let url = URL(string: "\(endpoint)/tx") else {
                continue
            }

            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
                request.httpBody = trimmedRawHex.data(using: .utf8)
                let (data, response) = try await SpectraNetworkRouter.shared.data(for: request, profile: .chainWrite)
                guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                    let message = String(data: data, encoding: .utf8) ?? "Unknown Bitcoin broadcast failure."
                    if classifySendBroadcastFailure(message) == .alreadyBroadcast, !fallbackTransactionHash.isEmpty {
                        return fallbackTransactionHash
                    }
                    throw BitcoinWalletEngineError.broadcastFailed(message)
                }

                let txid = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !txid.isEmpty {
                    recordEndpointAttempt(endpoint: endpoint, success: true)
                    return txid
                }
                if !fallbackTransactionHash.isEmpty {
                    recordEndpointAttempt(endpoint: endpoint, success: true)
                    return fallbackTransactionHash
                }
                throw BitcoinWalletEngineError.broadcastFailed("Bitcoin broadcast succeeded but no txid returned.")
            } catch {
                lastError = error
                recordEndpointAttempt(endpoint: endpoint, success: false)
                if classifySendBroadcastFailure(error.localizedDescription) == .alreadyBroadcast,
                   !fallbackTransactionHash.isEmpty {
                    return fallbackTransactionHash
                }
            }
        }

        throw lastError ?? URLError(.cannotConnectToHost)
    }

    private static func broadcastWithRecovery(
        transaction: Transaction,
        txid: String,
        providerIDs: Set<String>? = nil
    ) throws {
        let attempts = 2
        var lastError: Error?

        for _ in 0 ..< attempts {
            do {
                try performWithClientFallback(providerIDs: providerIDs) { client in
                    try client.broadcast(transaction: transaction)
                }
                return
            } catch {
                let disposition = classifySendBroadcastFailure(error.localizedDescription)
                if disposition == .alreadyBroadcast {
                    return
                }
                lastError = error
                if disposition != .retryable {
                    break
                }
            }
        }

        throw lastError ?? URLError(.cannotConnectToHost)
    }

    private static func verifyBroadcastedTransactionIfAvailable(
        txid: String,
        providerIDs: Set<String>? = nil
    ) -> SendBroadcastVerificationStatus {
        let trimmed = txid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .deferred }

        var sawNotFound = false
        var lastError: Error?

        for endpoint in orderedEsploraEndpoints(providerIDs: providerIDs) {
            guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: "\(endpoint)/tx/\(encoded)") else {
                continue
            }

            let semaphore = DispatchSemaphore(value: 0)
            var result: Result<Bool, Error> = .success(false)
            let task = URLSession.shared.dataTask(with: url) { _, response, error in
                defer { semaphore.signal() }
                if let error {
                    result = .failure(error)
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    result = .failure(URLError(.badServerResponse))
                    return
                }
                if (200 ..< 300).contains(http.statusCode) {
                    result = .success(true)
                } else if http.statusCode == 404 {
                    result = .success(false)
                } else {
                    result = .failure(URLError(.badServerResponse))
                }
            }
            task.resume()
            semaphore.wait()

            switch result {
            case .success(true):
                return .verified
            case .success(false):
                sawNotFound = true
            case .failure(let error):
                lastError = error
            }
        }

        if let lastError, !sawNotFound {
            return .failed(lastError.localizedDescription)
        }
        return .deferred
    }

    private static func orderedEsploraEndpoints(providerIDs: Set<String>? = nil) -> [String] {
        let counters = loadEndpointReliabilityCounters()
        return filteredEsploraEndpoints(providerIDs: providerIDs).sorted { lhs, rhs in
            let leftScore = endpointScore(counters[lhs])
            let rightScore = endpointScore(counters[rhs])
            if leftScore == rightScore {
                return lhs < rhs
            }
            return leftScore > rightScore
        }
    }

    private static func filteredEsploraEndpoints(providerIDs: Set<String>? = nil) -> [String] {
        let allEndpoints = resolvedEsploraEndpoints()
        guard let providerIDs, !providerIDs.isEmpty else {
            return allEndpoints
        }

        let normalized = Set(providerIDs.map { $0.lowercased() })
        let allowEsplora = normalized.contains("esplora")
        let allowMaestro = normalized.contains("maestro-esplora")
        let filtered = allEndpoints.filter { endpoint in
            let isMaestro = endpoint.contains("gomaestro-api.org")
            return isMaestro ? allowMaestro : allowEsplora
        }
        return filtered.isEmpty ? allEndpoints : filtered
    }

    private static func endpointScore(_ counter: EndpointReliabilityCounter?) -> Double {
        guard let counter else { return 0.5 }
        let attempts = max(1, counter.successCount + counter.failureCount)
        return Double(counter.successCount) / Double(attempts)
    }

    private static func loadEndpointReliabilityCounters() -> [String: EndpointReliabilityCounter] {
        guard let data = UserDefaults.standard.data(forKey: endpointReliabilityDefaultsKey),
              let decoded = try? JSONDecoder().decode([String: EndpointReliabilityCounter].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func saveEndpointReliabilityCounters(_ counters: [String: EndpointReliabilityCounter]) {
        guard let data = try? JSONEncoder().encode(counters) else { return }
        UserDefaults.standard.set(data, forKey: endpointReliabilityDefaultsKey)
    }

    private static func recordEndpointAttempt(endpoint: String, success: Bool) {
        var counters = loadEndpointReliabilityCounters()
        var counter = counters[endpoint] ?? EndpointReliabilityCounter(successCount: 0, failureCount: 0, lastUpdatedAt: 0)
        if success {
            counter.successCount += 1
        } else {
            counter.failureCount += 1
        }
        counter.lastUpdatedAt = Date().timeIntervalSince1970
        counters[endpoint] = counter
        saveEndpointReliabilityCounters(counters)
    }
}

enum BitcoinWalletEngineError: LocalizedError {
    case signingFailed
    case unsupportedDerivationPath(String)
    case broadcastFailed(String)
    case policyViolation(String)

    var errorDescription: String? {
        switch self {
        case .signingFailed:
            return NSLocalizedString("Bitcoin transaction signing failed.", comment: "")
        case .unsupportedDerivationPath(let derivationPath):
            let format = NSLocalizedString("Unsupported Bitcoin derivation path: %@", comment: "")
            return String(format: format, locale: .current, derivationPath)
        case .broadcastFailed(let message):
            return message
        case .policyViolation(let message):
            return message
        }
    }
}
