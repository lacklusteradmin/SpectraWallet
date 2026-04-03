import Foundation
import WalletCore
import SwiftProtobuf

enum StellarWalletEngineError: LocalizedError {
    case invalidAddress
    case invalidAmount
    case invalidSeedPhrase
    case invalidResponse
    case signingFailed(String)
    case networkError(String)
    case broadcastFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return CommonLocalization.invalidAddress("Stellar")
        case .invalidAmount:
            return CommonLocalization.invalidTransferAmount("Stellar")
        case .invalidSeedPhrase:
            return CommonLocalization.invalidSeedPhrase("Stellar")
        case .invalidResponse:
            return CommonLocalization.invalidProviderResponse("Stellar")
        case .signingFailed(let message):
            return CommonLocalization.signingFailed("Stellar", message: message)
        case .networkError(let message):
            return CommonLocalization.networkRequestFailed("Stellar", message: message)
        case .broadcastFailed(let message):
            return CommonLocalization.broadcastFailed("Stellar", message: message)
        }
    }
}

struct StellarSendPreview: Equatable {
    let estimatedNetworkFeeXLM: Double
    let feeStroops: Int64
    let sequence: Int64
    let spendableBalance: Double
    let feeRateDescription: String?
    let estimatedTransactionBytes: Int?
    let selectedInputCount: Int?
    let usesChangeOutput: Bool?
    let maxSendable: Double
}

struct StellarSendResult: Equatable {
    let transactionHash: String
    let estimatedNetworkFeeXLM: Double
    let signedEnvelopeXDR: String
    let verificationStatus: SendBroadcastVerificationStatus
}

enum StellarWalletEngine {
    private static let minimumBaseFeeStroops: Int64 = 100

    static func derivedAddress(for seedPhrase: String, derivationPath: String = "m/44'/148'/0'") throws -> String {
        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .stellar,
            derivationPath: derivationPath
        )
        let normalized = material.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AddressValidation.isValidStellarAddress(normalized) else {
            throw StellarWalletEngineError.invalidSeedPhrase
        }
        return normalized
    }

    static func derivedAddress(forPrivateKey privateKeyHex: String) throws -> String {
        let material = try WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .stellar)
        let normalized = material.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AddressValidation.isValidStellarAddress(normalized) else {
            throw StellarWalletEngineError.invalidAddress
        }
        return normalized
    }

    static func estimateSendPreview(
        from ownerAddress: String,
        to destinationAddress: String,
        amount: Double
    ) async throws -> StellarSendPreview {
        guard AddressValidation.isValidStellarAddress(ownerAddress),
              AddressValidation.isValidStellarAddress(destinationAddress) else {
            throw StellarWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw StellarWalletEngineError.invalidAmount
        }

        let feeStroops = max(minimumBaseFeeStroops, try await StellarBalanceService.fetchBaseFeeStroops())
        let sequence = try await StellarBalanceService.fetchSequence(for: ownerAddress)
        let estimatedNetworkFeeXLM = Double(feeStroops) / 10_000_000.0
        let balanceXLM = try await StellarBalanceService.fetchBalance(for: ownerAddress)
        let maxSendable = max(0, balanceXLM - estimatedNetworkFeeXLM)
        return StellarSendPreview(
            estimatedNetworkFeeXLM: estimatedNetworkFeeXLM,
            feeStroops: feeStroops,
            sequence: sequence,
            spendableBalance: maxSendable,
            feeRateDescription: "\(feeStroops) stroops",
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
        derivationPath: String = "m/44'/148'/0'",
        providerIDs: Set<String>? = nil
    ) async throws -> StellarSendResult {
        let preview = try await estimateSendPreview(from: ownerAddress, to: destinationAddress, amount: amount)
        let material = try WalletCoreDerivation.deriveMaterial(
            seedPhrase: seedPhrase,
            coin: .stellar,
            derivationPath: derivationPath
        )
        guard !material.privateKeyData.isEmpty else {
            throw StellarWalletEngineError.invalidSeedPhrase
        }
        guard material.address == ownerAddress else {
            throw StellarWalletEngineError.invalidAddress
        }
        let envelope = try signEnvelope(
            privateKey: material.privateKeyData,
            ownerAddress: ownerAddress,
            destinationAddress: destinationAddress,
            amount: amount,
            feeStroops: preview.feeStroops,
            sequence: preview.sequence
        )
        let hash: String
        do {
            hash = try await StellarBalanceService.submitTransaction(xdrEnvelope: envelope, providerIDs: providerIDs)
        } catch {
            guard classifySendBroadcastFailure(error.localizedDescription) == .alreadyBroadcast,
                  let recoveredHash = await recoverRecentTransactionHashIfAvailable(
                      ownerAddress: ownerAddress,
                      destinationAddress: destinationAddress,
                      amount: amount
                  ) else {
                throw error
            }
            hash = recoveredHash
        }
        let verificationStatus = await verifyBroadcastedTransactionIfAvailable(hash: hash)
        return StellarSendResult(
            transactionHash: hash,
            estimatedNetworkFeeXLM: preview.estimatedNetworkFeeXLM,
            signedEnvelopeXDR: envelope,
            verificationStatus: verificationStatus
        )
    }

    static func sendInBackground(
        privateKeyHex: String,
        ownerAddress: String,
        destinationAddress: String,
        amount: Double,
        providerIDs: Set<String>? = nil
    ) async throws -> StellarSendResult {
        let preview = try await estimateSendPreview(from: ownerAddress, to: destinationAddress, amount: amount)
        let material = try WalletCoreDerivation.deriveMaterial(privateKeyHex: privateKeyHex, coin: .stellar)
        guard material.address == ownerAddress else {
            throw StellarWalletEngineError.invalidAddress
        }
        let envelope = try signEnvelope(
            privateKey: material.privateKeyData,
            ownerAddress: ownerAddress,
            destinationAddress: destinationAddress,
            amount: amount,
            feeStroops: preview.feeStroops,
            sequence: preview.sequence
        )
        let hash: String
        do {
            hash = try await StellarBalanceService.submitTransaction(xdrEnvelope: envelope, providerIDs: providerIDs)
        } catch {
            guard classifySendBroadcastFailure(error.localizedDescription) == .alreadyBroadcast,
                  let recoveredHash = await recoverRecentTransactionHashIfAvailable(
                      ownerAddress: ownerAddress,
                      destinationAddress: destinationAddress,
                      amount: amount
                  ) else {
                throw error
            }
            hash = recoveredHash
        }
        let verificationStatus = await verifyBroadcastedTransactionIfAvailable(hash: hash)
        return StellarSendResult(
            transactionHash: hash,
            estimatedNetworkFeeXLM: preview.estimatedNetworkFeeXLM,
            signedEnvelopeXDR: envelope,
            verificationStatus: verificationStatus
        )
    }

    static func rebroadcastSignedTransactionInBackground(
        signedEnvelopeXDR: String,
        expectedTransactionHash: String? = nil,
        providerIDs: Set<String>? = nil
    ) async throws -> StellarSendResult {
        let normalizedEnvelope = signedEnvelopeXDR.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Data(base64Encoded: normalizedEnvelope) != nil else {
            throw StellarWalletEngineError.invalidResponse
        }
        let hash = try await StellarBalanceService.submitTransaction(xdrEnvelope: normalizedEnvelope, providerIDs: providerIDs)
        let transactionHash = expectedTransactionHash?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? expectedTransactionHash!.trimmingCharacters(in: .whitespacesAndNewlines)
            : hash
        return StellarSendResult(
            transactionHash: transactionHash,
            estimatedNetworkFeeXLM: 0,
            signedEnvelopeXDR: normalizedEnvelope,
            verificationStatus: await verifyBroadcastedTransactionIfAvailable(hash: transactionHash)
        )
    }

    private static func verifyBroadcastedTransactionIfAvailable(hash: String) async -> SendBroadcastVerificationStatus {
        let normalizedHash = hash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHash.isEmpty else { return .deferred }

        var lastError: Error?
        for attempt in 0 ..< 3 {
            for endpoint in StellarBalanceService.endpointCatalog() {
                do {
                    guard let encoded = normalizedHash.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                          let url = URL(string: "\(endpoint)/transactions/\(encoded)") else { continue }
                    let (data, response) = try await ProviderHTTP.data(from: url, profile: .chainRead)
                    guard let http = response as? HTTPURLResponse else {
                        throw StellarWalletEngineError.invalidResponse
                    }
                    if http.statusCode == 404 {
                        continue
                    }
                    guard (200 ... 299).contains(http.statusCode) else {
                        throw StellarWalletEngineError.networkError("HTTP \(http.statusCode)")
                    }
                    let lookup = try JSONDecoder().decode(StellarProvider.TransactionLookupResponse.self, from: data)
                    if lookup.successful == false {
                        return .failed("Stellar Horizon reported unsuccessful transaction execution.")
                    }
                    if lookup.hash?.caseInsensitiveCompare(normalizedHash) == .orderedSame || lookup.successful == true {
                        return .verified
                    }
                } catch {
                    lastError = error
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

    private static func recoverRecentTransactionHashIfAvailable(
        ownerAddress: String,
        destinationAddress: String,
        amount: Double
    ) async -> String? {
        let result = await StellarBalanceService.fetchRecentHistoryWithDiagnostics(for: ownerAddress, limit: 20)
        return result.snapshots.first {
            $0.kind == .send
                && abs($0.amount - amount) < 0.0000001
                && $0.counterpartyAddress.lowercased() == destinationAddress.lowercased()
        }?.transactionHash
    }

    private static func signEnvelope(
        privateKey: Data,
        ownerAddress: String,
        destinationAddress: String,
        amount: Double,
        feeStroops: Int64,
        sequence: Int64
    ) throws -> String {
        guard AddressValidation.isValidStellarAddress(ownerAddress),
              AddressValidation.isValidStellarAddress(destinationAddress) else {
            throw StellarWalletEngineError.invalidAddress
        }
        let amountStroops = try StellarBalanceService.stroops(fromXLM: amount)

        let input = StellarSigningInput.with {
            $0.account = ownerAddress
            $0.privateKey = privateKey
            $0.fee = Int32(clamping: feeStroops)
            $0.sequence = sequence
            $0.passphrase = StellarPassphrase.stellar.description
            $0.opPayment = StellarOperationPayment.with {
                $0.destination = destinationAddress
                $0.amount = amountStroops
            }
        }
        let output: StellarSigningOutput = AnySigner.sign(input: input, coin: .stellar)
        let signedEnvelope = output.signature.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !signedEnvelope.isEmpty else {
            let message = output.errorMessage.isEmpty ? "WalletCore returned an empty Stellar envelope." : output.errorMessage
            throw StellarWalletEngineError.signingFailed(message)
        }
        return signedEnvelope
    }
}
