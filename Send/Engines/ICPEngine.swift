import Foundation
import SwiftProtobuf
import WalletCore

enum ICPWalletEngineError: LocalizedError {
    case invalidAddress
    case invalidAmount
    case invalidSeedPhrase
    case invalidResponse
    case insufficientBalance
    case signingFailed(String)
    case networkError(String)
    case broadcastFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return AppLocalization.string("The ICP account identifier is not valid.")
        case .invalidAmount:
            return CommonLocalization.invalidTransferAmount("ICP")
        case .invalidSeedPhrase:
            return CommonLocalization.invalidSeedPhrase("ICP")
        case .invalidResponse:
            return CommonLocalization.invalidProviderResponse("ICP")
        case .insufficientBalance:
            return AppLocalization.string("Insufficient ICP to cover amount and network fee.")
        case .signingFailed(let message):
            return CommonLocalization.signingFailed("ICP", message: message)
        case .networkError(let message):
            return CommonLocalization.networkRequestFailed("ICP", message: message)
        case .broadcastFailed(let message):
            return CommonLocalization.broadcastFailed("ICP", message: message)
        }
    }
}

struct ICPSendPreview: Equatable {
    let estimatedNetworkFeeICP: Double
    let feeE8s: UInt64
    let spendableBalance: Double
    let feeRateDescription: String?
    let estimatedTransactionBytes: Int?
    let selectedInputCount: Int?
    let usesChangeOutput: Bool?
    let maxSendable: Double
}

struct ICPSendResult: Equatable {
    let transactionHash: String
    let estimatedNetworkFeeICP: Double
    let signedTransactionHex: String
    let verificationStatus: SendBroadcastVerificationStatus
}

enum ICPWalletEngine {
    private static let defaultMemo: UInt64 = 0
    private static let permittedDriftNanos: UInt64 = 60_000_000_000

    static func derivedAddress(for seedPhrase: String, derivationPath: String = "m/44'/223'/0'/0/0") throws -> String {
        do {
            return try SeedPhraseAddressDerivation.address(
                for: seedPhrase,
                coin: .internetComputer,
                derivationPath: derivationPath,
                normalizer: { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() },
                validator: AddressValidation.isValidICPAddress
            )
        } catch {
            throw ICPWalletEngineError.invalidSeedPhrase
        }
    }

    static func derivedAddress(forPrivateKey privateKeyHex: String) throws -> String {
        do {
            return try SeedPhraseAddressDerivation.address(
                forPrivateKey: privateKeyHex,
                coin: .internetComputer,
                normalizer: { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() },
                validator: AddressValidation.isValidICPAddress
            )
        } catch {
            throw ICPWalletEngineError.invalidAddress
        }
    }

    static func estimateSendPreview(from ownerAddress: String, to destinationAddress: String, amount: Double) async throws -> ICPSendPreview {
        let normalizedOwner = normalizeAddress(ownerAddress)
        let normalizedDestination = normalizeAddress(destinationAddress)
        guard AddressValidation.isValidICPAddress(normalizedOwner),
              AddressValidation.isValidICPAddress(normalizedDestination) else {
            throw ICPWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw ICPWalletEngineError.invalidAmount
        }
        let feeE8s = try await ICPBalanceService.fetchSuggestedTransferFeeE8s()
        let estimatedNetworkFeeICP = Double(feeE8s) / 100_000_000.0
        let balanceICP = try await ICPBalanceService.fetchBalance(for: normalizedOwner)
        let maxSendable = max(0, balanceICP - estimatedNetworkFeeICP)
        return ICPSendPreview(
            estimatedNetworkFeeICP: estimatedNetworkFeeICP,
            feeE8s: feeE8s,
            spendableBalance: maxSendable,
            feeRateDescription: "\(feeE8s) e8s",
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
        derivationPath: String = "m/44'/223'/0'/0/0"
    ) async throws -> ICPSendResult {
        let normalizedOwner = normalizeAddress(ownerAddress)
        let normalizedDestination = normalizeAddress(destinationAddress)
        guard AddressValidation.isValidICPAddress(normalizedOwner),
              AddressValidation.isValidICPAddress(normalizedDestination) else {
            throw ICPWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw ICPWalletEngineError.invalidAmount
        }

        let preview = try await estimateSendPreview(from: normalizedOwner, to: normalizedDestination, amount: amount)
        let amountE8s = try scaledUnsignedAmount(amount, decimals: 8)
        let balanceICP = try await ICPBalanceService.fetchBalance(for: normalizedOwner)
        guard balanceICP + 0.00000001 >= amount + preview.estimatedNetworkFeeICP else {
            throw ICPWalletEngineError.insufficientBalance
        }

        let material = try SeedPhraseSigningMaterial.material(
            seedPhrase: seedPhrase,
            coin: .internetComputer,
            derivationPath: derivationPath
        )
        guard normalizeAddress(material.address) == normalizedOwner else {
            throw ICPWalletEngineError.invalidAddress
        }

        let signedTransaction = try signTransaction(
            privateKey: material.privateKeyData,
            destinationAddress: normalizedDestination,
            amountE8s: amountE8s
        )
        let hash: String
        do {
            hash = try await ICPBalanceService.submitSignedTransaction(signedTransaction.hexEncodedString())
        } catch {
            guard classifySendBroadcastFailure(error.localizedDescription) == .alreadyBroadcast,
                  let recoveredHash = await recoverRecentTransactionHashIfAvailable(
                      ownerAddress: normalizedOwner,
                      destinationAddress: normalizedDestination,
                      amount: amount
                  ) else {
                throw error
            }
            hash = recoveredHash
        }
        return ICPSendResult(
            transactionHash: hash,
            estimatedNetworkFeeICP: preview.estimatedNetworkFeeICP,
            signedTransactionHex: signedTransaction.hexEncodedString(),
            verificationStatus: await verifyBroadcastedTransactionIfAvailable(ownerAddress: normalizedOwner, transactionHash: hash)
        )
    }

    static func sendInBackground(
        privateKeyHex: String,
        ownerAddress: String,
        destinationAddress: String,
        amount: Double
    ) async throws -> ICPSendResult {
        let normalizedOwner = normalizeAddress(ownerAddress)
        let normalizedDestination = normalizeAddress(destinationAddress)
        guard AddressValidation.isValidICPAddress(normalizedOwner),
              AddressValidation.isValidICPAddress(normalizedDestination) else {
            throw ICPWalletEngineError.invalidAddress
        }
        guard amount > 0 else {
            throw ICPWalletEngineError.invalidAmount
        }

        let preview = try await estimateSendPreview(from: normalizedOwner, to: normalizedDestination, amount: amount)
        let amountE8s = try scaledUnsignedAmount(amount, decimals: 8)
        let balanceICP = try await ICPBalanceService.fetchBalance(for: normalizedOwner)
        guard balanceICP + 0.00000001 >= amount + preview.estimatedNetworkFeeICP else {
            throw ICPWalletEngineError.insufficientBalance
        }

        let material = try SeedPhraseSigningMaterial.material(privateKeyHex: privateKeyHex, coin: .internetComputer)
        guard normalizeAddress(material.address) == normalizedOwner else {
            throw ICPWalletEngineError.invalidAddress
        }

        let signedTransaction = try signTransaction(
            privateKey: material.privateKeyData,
            destinationAddress: normalizedDestination,
            amountE8s: amountE8s
        )
        let hash: String
        do {
            hash = try await ICPBalanceService.submitSignedTransaction(signedTransaction.hexEncodedString())
        } catch {
            guard classifySendBroadcastFailure(error.localizedDescription) == .alreadyBroadcast,
                  let recoveredHash = await recoverRecentTransactionHashIfAvailable(
                      ownerAddress: normalizedOwner,
                      destinationAddress: normalizedDestination,
                      amount: amount
                  ) else {
                throw error
            }
            hash = recoveredHash
        }
        return ICPSendResult(
            transactionHash: hash,
            estimatedNetworkFeeICP: preview.estimatedNetworkFeeICP,
            signedTransactionHex: signedTransaction.hexEncodedString(),
            verificationStatus: await verifyBroadcastedTransactionIfAvailable(ownerAddress: normalizedOwner, transactionHash: hash)
        )
    }

    static func rebroadcastSignedTransactionInBackground(
        signedTransactionHex: String,
        expectedTransactionHash: String? = nil
    ) async throws -> ICPSendResult {
        let normalizedTransaction = signedTransactionHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTransaction.isEmpty,
              Data(hexEncoded: normalizedTransaction) != nil else {
            throw ICPWalletEngineError.invalidResponse
        }
        let hash = try await ICPBalanceService.submitSignedTransaction(normalizedTransaction)
        let transactionHash = expectedTransactionHash?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? expectedTransactionHash!.trimmingCharacters(in: .whitespacesAndNewlines)
            : hash
        return ICPSendResult(
            transactionHash: transactionHash,
            estimatedNetworkFeeICP: 0,
            signedTransactionHex: normalizedTransaction,
            verificationStatus: await ICPBalanceService.verifyTransactionIfAvailable(transactionHash)
        )
    }

    private static func verifyBroadcastedTransactionIfAvailable(
        ownerAddress: String,
        transactionHash: String
    ) async -> SendBroadcastVerificationStatus {
        await ICPBalanceService.verifyTransactionIfAvailable(transactionHash)
    }

    private static func recoverRecentTransactionHashIfAvailable(
        ownerAddress: String,
        destinationAddress: String,
        amount: Double
    ) async -> String? {
        let result = await ICPBalanceService.fetchRecentHistoryWithDiagnostics(for: ownerAddress, limit: 20)
        return result.snapshots.first {
            $0.kind == .send
                && abs($0.amount - amount) < 0.00000001
                && normalizeAddress($0.counterpartyAddress) == normalizeAddress(destinationAddress)
        }?.transactionHash
    }

    private static func signTransaction(
        privateKey: Data,
        destinationAddress: String,
        amountE8s: UInt64
    ) throws -> Data {
        var transaction = InternetComputerTransaction()
        transaction.transfer = InternetComputerTransaction.Transfer.with {
            $0.toAccountIdentifier = destinationAddress
            $0.amount = amountE8s
            $0.memo = defaultMemo
            $0.currentTimestampNanos = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
            $0.permittedDrift = permittedDriftNanos
        }

        let input = InternetComputerSigningInput.with {
            $0.privateKey = privateKey
            $0.transaction = transaction
        }

        let output: InternetComputerSigningOutput = AnySigner.sign(input: input, coin: .internetComputer)
        guard output.error == .ok else {
            let message = output.errorMessage.isEmpty ? "WalletCore returned signing error code \(output.error.rawValue)." : output.errorMessage
            throw ICPWalletEngineError.signingFailed(message)
        }
        guard !output.signedTransaction.isEmpty else {
            throw ICPWalletEngineError.signingFailed("WalletCore returned an empty signed ICP transaction.")
        }
        return output.signedTransaction
    }

    private static func normalizeAddress(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func scaledUnsignedAmount(_ amount: Double, decimals: Int) throws -> UInt64 {
        guard amount.isFinite, amount > 0, decimals >= 0 else {
            throw ICPWalletEngineError.invalidAmount
        }
        let base = NSDecimalNumber(decimal: decimalPowerOfTen(decimals))
        let scaled = NSDecimalNumber(value: amount).multiplying(by: base).rounding(accordingToBehavior: nil)
        if scaled == NSDecimalNumber.notANumber || scaled.compare(NSDecimalNumber.zero) != .orderedDescending {
            throw ICPWalletEngineError.invalidAmount
        }
        let maxValue = NSDecimalNumber(value: UInt64.max)
        guard scaled.compare(maxValue) != .orderedDescending else {
            throw ICPWalletEngineError.invalidAmount
        }
        return scaled.uint64Value
    }

    private static func decimalPowerOfTen(_ exponent: Int) -> Decimal {
        var result = Decimal(1)
        for _ in 0 ..< exponent {
            result *= 10
        }
        return result
    }
}

private extension Data {
    func hexEncodedString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}
