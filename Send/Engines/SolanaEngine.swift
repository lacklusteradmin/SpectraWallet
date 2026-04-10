import Foundation
import SolanaSwift
import WalletCore

enum SolanaWalletEngineError: LocalizedError {
    case invalidAddress
    case invalidAmount
    case invalidSeedPhrase
    case signingFailed(String)
    case rpcFailed(String)
    case broadcastFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return CommonLocalization.invalidAddress("Solana")
        case .invalidAmount:
            return CommonLocalization.invalidTransferAmount("Solana")
        case .invalidSeedPhrase:
            return CommonLocalization.invalidSeedPhrase("Solana")
        case .signingFailed(let message):
            return CommonLocalization.signingFailed("Solana", message: message)
        case .rpcFailed(let message):
            let format = AppLocalization.string("Solana RPC failed: %@")
            return String(format: format, locale: AppLocalization.locale, AppLocalization.string(message))
        case .broadcastFailed(let message):
            return CommonLocalization.broadcastFailed("Solana", message: message)
        }
    }
}

struct SolanaSendPreview: Equatable {
    let estimatedNetworkFeeSOL: Double
    let spendableBalance: Double
    let feeRateDescription: String?
    let estimatedTransactionBytes: Int?
    let selectedInputCount: Int?
    let usesChangeOutput: Bool?
    let maxSendable: Double
}

struct SolanaSendResult: Equatable {
    let transactionHash: String
    let estimatedNetworkFeeSOL: Double
    let signedTransactionBase64: String
    let verificationStatus: SendBroadcastVerificationStatus
}

enum SolanaWalletEngine {
    // Primary Solana wallet path used by major wallets.
    private static let primaryDerivationPath = "m/44'/501'/0'/0'"
    private static let maxSerializedTransactionBytes = 1232

    enum DerivationPreference {
        case standard
        case legacy
    }

    private static func rpcClient(baseURL: String) -> SolanaAPIClient {
        SolanaProvider.rpcClient(baseURL: baseURL)
    }

    private static func withRPCClient<T>(
        providerIDs: Set<String>? = nil,
        _ operation: (SolanaAPIClient) async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for baseURL in orderedRPCBases(providerIDs: providerIDs) {
            do {
                let result = try await operation(rpcClient(baseURL: baseURL))
                ChainEndpointReliability.recordAttempt(namespace: SolanaProvider.endpointReliabilityNamespace, endpoint: baseURL, success: true)
                return result
            } catch {
                lastError = error
                ChainEndpointReliability.recordAttempt(namespace: SolanaProvider.endpointReliabilityNamespace, endpoint: baseURL, success: false)
            }
        }
        throw lastError ?? SolanaWalletEngineError.rpcFailed("No Solana RPC endpoint was reachable.")
    }

    static func derivedAddress(
        for seedPhrase: String,
        preference: DerivationPreference = .standard,
        account: UInt32 = 0
    ) throws -> String {
        do {
            return try SeedPhraseAddressDerivation.solanaAddress(
                seedPhrase: seedPhrase,
                preference: preference,
                account: account
            )
        } catch {
            throw SolanaWalletEngineError.invalidSeedPhrase
        }
    }

    static func estimateSendPreview(from ownerAddress: String, to destinationAddress: String, amount: Double) async throws -> SolanaSendPreview {
        guard AddressValidation.isValidSolanaAddress(ownerAddress), AddressValidation.isValidSolanaAddress(destinationAddress) else {
            throw SolanaWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw SolanaWalletEngineError.invalidAmount
        }
        let balance = try await SolanaBalanceService.fetchBalance(for: ownerAddress)
        let estimatedFeeSOL = try await fetchEstimatedNetworkFeeSOL()
        let maxSendable = max(0, balance - estimatedFeeSOL)
        return SolanaSendPreview(
            estimatedNetworkFeeSOL: estimatedFeeSOL,
            spendableBalance: maxSendable,
            feeRateDescription: "Live RPC fee calculator",
            estimatedTransactionBytes: nil,
            selectedInputCount: nil,
            usesChangeOutput: nil,
            maxSendable: maxSendable
        )
    }

    static func sendInBackground(
        seedPhrase: String,
        ownerAddress: String,
        destinationAddress: String,
        amount: Double,
        preference: DerivationPreference = .standard,
        account: UInt32 = 0,
        providerIDs: Set<String>? = nil
    ) async throws -> SolanaSendResult {
        let normalizedOwner = ownerAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDestination = destinationAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        guard AddressValidation.isValidSolanaAddress(normalizedOwner),
              AddressValidation.isValidSolanaAddress(normalizedDestination) else {
            throw SolanaWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw SolanaWalletEngineError.invalidAmount
        }

        let lamports = try scaledUnsignedAmount(amount, decimals: 9)
        guard lamports > 0 else {
            throw SolanaWalletEngineError.invalidAmount
        }

        let resolvedKey = try resolvedSolanaKeyMaterial(
            seedPhrase: seedPhrase,
            ownerAddress: normalizedOwner,
            preferredDerivationPath: preferredSolanaPath(preference: preference, account: account),
            account: account
        )
        let privateKey = resolvedKey.privateKeyData

        let latestBlockhash = try await fetchLatestBlockhash(providerIDs: providerIDs)

        var transfer = SolanaTransfer()
        transfer.recipient = normalizedDestination
        transfer.value = lamports

        var input = SolanaSigningInput()
        input.privateKey = privateKey
        input.recentBlockhash = latestBlockhash
        input.sender = normalizedOwner
        input.transferTransaction = transfer
        input.txEncoding = .base64

        let output: SolanaSigningOutput = AnySigner.sign(input: input, coin: .solana)
        if output.error != .ok {
            let message = output.errorMessage.isEmpty ? "WalletCore returned signing error code \(output.error.rawValue)." : output.errorMessage
            throw SolanaWalletEngineError.signingFailed(message)
        }
        let encodedTransaction = output.encoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !encodedTransaction.isEmpty else {
            throw SolanaWalletEngineError.signingFailed("WalletCore returned an empty transaction payload.")
        }
        try validateSerializedTransactionPolicy(encodedTransaction)

        let txHash = try await broadcastSignedTransaction(encodedTransaction, providerIDs: providerIDs)
        let verificationStatus = await verifyBroadcastedTransactionIfAvailable(signature: txHash)
        let estimatedNetworkFeeSOL = try await fetchEstimatedNetworkFeeSOL(providerIDs: providerIDs)
        return SolanaSendResult(
            transactionHash: txHash,
            estimatedNetworkFeeSOL: estimatedNetworkFeeSOL,
            signedTransactionBase64: encodedTransaction,
            verificationStatus: verificationStatus
        )
    }

    static func sendTokenInBackground(
        seedPhrase: String,
        ownerAddress: String,
        destinationAddress: String,
        mintAddress: String,
        decimals: Int,
        amount: Double,
        sourceTokenAccountAddress: String?,
        preference: DerivationPreference = .standard,
        account: UInt32 = 0,
        providerIDs: Set<String>? = nil
    ) async throws -> SolanaSendResult {
        let normalizedOwner = ownerAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDestination = destinationAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMint = mintAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        guard AddressValidation.isValidSolanaAddress(normalizedOwner),
              AddressValidation.isValidSolanaAddress(normalizedDestination),
              AddressValidation.isValidSolanaAddress(normalizedMint) else {
            throw SolanaWalletEngineError.invalidAddress
        }
        guard amount > 0, decimals >= 0 else {
            throw SolanaWalletEngineError.invalidAmount
        }

        let rawAmount = try scaledUnsignedAmount(amount, decimals: decimals)
        guard rawAmount > 0 else {
            throw SolanaWalletEngineError.invalidAmount
        }

        let ownerPublicKey = try PublicKey(string: normalizedOwner)
        let destinationPublicKey = try PublicKey(string: normalizedDestination)
        let mintPublicKey = try PublicKey(string: normalizedMint)

        let resolvedSourceTokenAccount: String
        if let sourceTokenAccountAddress,
           AddressValidation.isValidSolanaAddress(sourceTokenAccountAddress) {
            resolvedSourceTokenAccount = sourceTokenAccountAddress
        } else {
            resolvedSourceTokenAccount = try PublicKey.associatedTokenAddress(
                walletAddress: ownerPublicKey,
                tokenMintAddress: mintPublicKey,
                tokenProgramId: TokenProgram.id
            ).base58EncodedString
        }

        let destinationTokenAccount = try PublicKey.associatedTokenAddress(
            walletAddress: destinationPublicKey,
            tokenMintAddress: mintPublicKey,
            tokenProgramId: TokenProgram.id
        ).base58EncodedString

        let resolvedKey = try resolvedSolanaKeyMaterial(
            seedPhrase: seedPhrase,
            ownerAddress: normalizedOwner,
            preferredDerivationPath: preferredSolanaPath(preference: preference, account: account),
            account: account
        )
        let privateKey = resolvedKey.privateKeyData
        let latestBlockhash = try await fetchLatestBlockhash(providerIDs: providerIDs)

        var message = SolanaCreateAndTransferToken()
        message.recipientMainAddress = normalizedDestination
        message.tokenMintAddress = normalizedMint
        message.recipientTokenAddress = destinationTokenAccount
        message.senderTokenAddress = resolvedSourceTokenAccount
        message.amount = rawAmount
        message.decimals = UInt32(decimals)

        var input = SolanaSigningInput()
        input.privateKey = privateKey
        input.recentBlockhash = latestBlockhash
        input.sender = normalizedOwner
        input.createAndTransferTokenTransaction = message
        input.txEncoding = .base64

        let output: SolanaSigningOutput = AnySigner.sign(input: input, coin: .solana)
        if output.error != .ok {
            let message = output.errorMessage.isEmpty ? "WalletCore returned signing error code \(output.error.rawValue)." : output.errorMessage
            throw SolanaWalletEngineError.signingFailed(message)
        }
        let encodedTransaction = output.encoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !encodedTransaction.isEmpty else {
            throw SolanaWalletEngineError.signingFailed("WalletCore returned an empty token transaction payload.")
        }
        try validateSerializedTransactionPolicy(encodedTransaction)

        let txHash = try await broadcastSignedTransaction(encodedTransaction, providerIDs: providerIDs)
        let verificationStatus = await verifyBroadcastedTransactionIfAvailable(signature: txHash)
        let estimatedNetworkFeeSOL = try await fetchEstimatedNetworkFeeSOL(providerIDs: providerIDs)
        return SolanaSendResult(
            transactionHash: txHash,
            estimatedNetworkFeeSOL: estimatedNetworkFeeSOL,
            signedTransactionBase64: encodedTransaction,
            verificationStatus: verificationStatus
        )
    }

    static func rebroadcastSignedTransactionInBackground(
        signedTransactionBase64: String,
        expectedTransactionHash: String? = nil,
        providerIDs: Set<String>? = nil
    ) async throws -> SolanaSendResult {
        let normalizedPayload = signedTransactionBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        try validateSerializedTransactionPolicy(normalizedPayload)
        let txHash = try await broadcastSignedTransaction(normalizedPayload, providerIDs: providerIDs)
        let transactionHash = expectedTransactionHash?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? expectedTransactionHash!.trimmingCharacters(in: .whitespacesAndNewlines)
            : txHash
        return SolanaSendResult(
            transactionHash: transactionHash,
            estimatedNetworkFeeSOL: 0,
            signedTransactionBase64: normalizedPayload,
            verificationStatus: await verifyBroadcastedTransactionIfAvailable(signature: transactionHash)
        )
    }

    private static func verifyBroadcastedTransactionIfAvailable(signature: String) async -> SendBroadcastVerificationStatus {
        let normalizedSignature = signature.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSignature.isEmpty else { return .deferred }

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getSignatureStatuses",
            "params": [
                [normalizedSignature],
                ["searchTransactionHistory": true]
            ]
        ]

        var lastError: Error?
        for attempt in 0 ..< 3 {
            for baseURL in orderedRPCBases() {
                do {
                    guard let url = URL(string: baseURL) else { continue }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 20
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

                    let (data, response) = try await ProviderHTTP.data(for: request, profile: .chainRead)
                    guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                        throw SolanaWalletEngineError.rpcFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                    }
                    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let result = object["result"] as? [String: Any],
                          let values = result["value"] as? [Any],
                          let first = values.first else {
                        throw SolanaWalletEngineError.rpcFailed("Invalid signature status payload.")
                    }

                    if first is NSNull {
                        continue
                    }
                    guard let status = first as? [String: Any] else {
                        throw SolanaWalletEngineError.rpcFailed("Invalid signature status entry.")
                    }
                    if let err = status["err"], !(err is NSNull) {
                        return .failed("Solana reported transaction error: \(err)")
                    }
                    if status["confirmationStatus"] != nil || status["confirmations"] != nil || status["slot"] != nil {
                        ChainEndpointReliability.recordAttempt(namespace: SolanaProvider.endpointReliabilityNamespace, endpoint: baseURL, success: true)
                        return .verified
                    }
                } catch {
                    lastError = error
                    ChainEndpointReliability.recordAttempt(namespace: SolanaProvider.endpointReliabilityNamespace, endpoint: baseURL, success: false)
                }
            }

            if attempt < 2 {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        if let lastError {
            return .failed(lastError.localizedDescription)
        }
        return .deferred
    }

    private static func fetchEstimatedNetworkFeeSOL(providerIDs: Set<String>? = nil) async throws -> Double {
        let lamports = try await fetchCurrentFeeLamports(providerIDs: providerIDs)
        return Double(lamports) / 1_000_000_000.0
    }

    private static func fetchCurrentFeeLamports(providerIDs: Set<String>? = nil) async throws -> UInt64 {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getFees",
            "params": [["commitment": "confirmed"]]
        ]

        var lastError: Error?
        for baseURL in orderedRPCBases(providerIDs: providerIDs) {
            do {
                guard let url = URL(string: baseURL) else { continue }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 20
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

                let (data, response) = try await ProviderHTTP.data(for: request, profile: .chainRead)
                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                    throw SolanaWalletEngineError.rpcFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                }
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let result = object["result"] as? [String: Any],
                      let value = result["value"] as? [String: Any],
                      let feeCalculator = value["feeCalculator"] as? [String: Any],
                      let lamports = feeCalculator["lamportsPerSignature"] as? NSNumber,
                      lamports.uint64Value > 0 else {
                    throw SolanaWalletEngineError.rpcFailed("Missing live fee calculator data.")
                }
                ChainEndpointReliability.recordAttempt(namespace: SolanaProvider.endpointReliabilityNamespace, endpoint: baseURL, success: true)
                return lamports.uint64Value
            } catch {
                lastError = error
                ChainEndpointReliability.recordAttempt(namespace: SolanaProvider.endpointReliabilityNamespace, endpoint: baseURL, success: false)
            }
        }

        if let lastError {
            throw lastError
        }
        throw SolanaWalletEngineError.rpcFailed("Missing live fee calculator data.")
    }

    private static func fetchLatestBlockhash(providerIDs: Set<String>? = nil) async throws -> String {
        let hash = try await withRPCClient(providerIDs: providerIDs) { client in
            try await client.getRecentBlockhash(commitment: "confirmed")
        }.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hash.isEmpty else {
            throw SolanaWalletEngineError.rpcFailed("Latest blockhash was empty.")
        }
        return hash
    }

    private static func broadcastSignedTransaction(
        _ encodedTransactionBase64: String,
        providerIDs: Set<String>? = nil
    ) async throws -> String {
        try validateSerializedTransactionPolicy(encodedTransactionBase64)
        guard let config = RequestConfiguration(
            commitment: "confirmed",
            encoding: "base64",
            skipPreflight: false,
            preflightCommitment: "confirmed"
        ) else {
            throw SolanaWalletEngineError.broadcastFailed("Failed to build Solana transaction config.")
        }
        let fallbackSignature = recoverSignature(fromEncodedTransaction: encodedTransactionBase64)
        let attempts = 2
        var lastError: Error?

        for _ in 0 ..< attempts {
            do {
                let signature = try await withRPCClient(providerIDs: providerIDs) { client in
                    try await client.sendTransaction(
                        transaction: encodedTransactionBase64,
                        configs: config
                    )
                }
                let txHash = signature.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !txHash.isEmpty else {
                    throw SolanaWalletEngineError.broadcastFailed("Provider did not return a transaction hash.")
                }
                return txHash
            } catch {
                let disposition = classifySendBroadcastFailure(error.localizedDescription)
                if disposition == .alreadyBroadcast, !fallbackSignature.isEmpty {
                    return fallbackSignature
                }
                lastError = error
                if disposition != .retryable {
                    break
                }
            }
        }

        throw lastError ?? SolanaWalletEngineError.broadcastFailed("Provider did not return a transaction hash.")
    }

    private static func validateSerializedTransactionPolicy(_ encodedTransactionBase64: String) throws {
        let normalizedPayload = encodedTransactionBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let payload = Data(base64Encoded: normalizedPayload), !payload.isEmpty else {
            throw SolanaWalletEngineError.signingFailed("Invalid signed Solana transaction payload.")
        }
        guard payload.count <= maxSerializedTransactionBytes else {
            throw SolanaWalletEngineError.broadcastFailed("Solana transaction exceeds the standard packet size limit.")
        }
    }

    private static func recoverSignature(fromEncodedTransaction encodedTransactionBase64: String) -> String {
        guard let payload = Data(base64Encoded: encodedTransactionBase64),
              !payload.isEmpty else {
            return ""
        }

        let signatureCount = Int(payload[0])
        guard signatureCount > 0 else { return "" }

        let signatureLength = 64
        let signatureStart = 1
        let signatureEnd = signatureStart + signatureLength
        guard payload.count >= signatureEnd else { return "" }

        let signatureData = payload.subdata(in: signatureStart ..< signatureEnd)
        return base58Encode(signatureData)
    }

    private static func base58Encode(_ data: Data) -> String {
        let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        guard !data.isEmpty else { return "" }

        var bytes = [UInt8](data)
        var zeros = 0
        while zeros < bytes.count, bytes[zeros] == 0 {
            zeros += 1
        }

        var encoded: [Character] = []
        var startAt = zeros
        while startAt < bytes.count {
            var remainder = 0
            for index in startAt ..< bytes.count {
                let value = Int(bytes[index]) + (remainder << 8)
                bytes[index] = UInt8(value / 58)
                remainder = value % 58
            }
            encoded.append(alphabet[remainder])
            while startAt < bytes.count, bytes[startAt] == 0 {
                startAt += 1
            }
        }

        if zeros > 0 {
            encoded.append(contentsOf: repeatElement(alphabet[0], count: zeros))
        }

        return String(encoded.reversed())
    }

    private static func scaledUnsignedAmount(_ amount: Double, decimals: Int) throws -> UInt64 {
        guard amount.isFinite, amount > 0, decimals >= 0 else {
            throw SolanaWalletEngineError.invalidAmount
        }
        let base = NSDecimalNumber(decimal: decimalPowerOfTen(decimals))
        let amountDecimal = NSDecimalNumber(value: amount)
        let scaled = amountDecimal.multiplying(by: base)
        let rounded = scaled.rounding(accordingToBehavior: nil)
        if rounded == NSDecimalNumber.notANumber || rounded.compare(NSDecimalNumber.zero) != .orderedDescending {
            throw SolanaWalletEngineError.invalidAmount
        }
        let maxValue = NSDecimalNumber(value: UInt64.max)
        guard rounded.compare(maxValue) != .orderedDescending else {
            throw SolanaWalletEngineError.invalidAmount
        }
        let value = rounded.uint64Value
        guard value > 0 else {
            throw SolanaWalletEngineError.invalidAmount
        }
        return value
    }

    private static func decimalPowerOfTen(_ exponent: Int) -> Decimal {
        guard exponent > 0 else { return 1 }
        var result = Decimal(1)
        for _ in 0 ..< exponent {
            result *= 10
        }
        return result
    }

    private struct SolanaKeyMaterial {
        let address: String
        let privateKeyData: Data
        let derivationPath: String
    }

    private static func resolvedSolanaKeyMaterial(
        seedPhrase: String,
        ownerAddress: String?,
        preferredDerivationPath: String? = nil,
        account: UInt32 = 0
    ) throws -> SolanaKeyMaterial {
        do {
            let resolved = try SeedPhraseSigningMaterial.resolvedSolanaKeyMaterial(
                seedPhrase: seedPhrase,
                ownerAddress: ownerAddress,
                preferredDerivationPath: preferredDerivationPath,
                account: account
            )
            return SolanaKeyMaterial(
                address: resolved.address,
                privateKeyData: resolved.privateKeyData,
                derivationPath: resolved.derivationPath
            )
        } catch {
            throw SolanaWalletEngineError.invalidSeedPhrase
        }
    }

    private static func supportedDerivationPaths(for account: UInt32) -> [String] {
        [
            "m/44'/501'/\(account)'/0'",
            "m/44'/501'/\(account)'"
        ]
    }

    private static func preferredSolanaPath(preference: DerivationPreference, account: UInt32) -> String {
        switch preference {
        case .standard:
            return "m/44'/501'/\(account)'/0'"
        case .legacy:
            return "m/44'/501'/\(account)'"
        }
    }

    private static func orderedRPCBases(providerIDs: Set<String>? = nil) -> [String] {
        SolanaProvider.orderedSendRPCBaseURLs(providerIDs: providerIDs)
    }

    private static func filteredRPCBases(providerIDs: Set<String>? = nil) -> [String] {
        SolanaProvider.filteredSendRPCBaseURLs(providerIDs: providerIDs)
    }
}
