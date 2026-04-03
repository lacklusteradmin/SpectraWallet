import Foundation

struct UTXOSatVBytePolicy {
    let chainName: String
    let baseUnitsPerCoin: Double
    let dustThreshold: UInt64
    let minimumRelayFeeRate: UInt64
    let minimumAbsoluteFee: UInt64
    let maxStandardTransactionBytes: UInt64

    func estimatedFee(estimatedBytes: Int, feeRate: UInt64) -> UInt64 {
        max(minimumAbsoluteFee, UInt64(Double(estimatedBytes) * Double(feeRate)))
    }

    func estimatedFee(inputCount: Int, outputCount: Int, feeRate: UInt64) -> UInt64 {
        estimatedFee(
            estimatedBytes: UTXOSpendPlanner.estimateTransactionBytes(
                inputCount: inputCount,
                outputCount: outputCount
            ),
            feeRate: feeRate
        )
    }

    func preview(for totalInputValue: UInt64, inputCount: Int, feeRate: UInt64) -> (estimatedBytes: Int, estimatedFee: UInt64, spendable: UInt64) {
        let estimatedBytes = UTXOSpendPlanner.estimateTransactionBytes(
            inputCount: max(1, inputCount),
            outputCount: 1
        )
        let estimatedFee = estimatedFee(estimatedBytes: estimatedBytes, feeRate: feeRate)
        let spendable = totalInputValue > estimatedFee ? totalInputValue - estimatedFee : 0
        return (estimatedBytes, estimatedFee, spendable)
    }

    func validatePlan<T>(
        sendAmount: UInt64,
        spendPlan: UTXOSpendPlan<T>,
        feeRate: UInt64,
        error: (String) -> Error,
        insufficientFunds: Error
    ) throws {
        guard sendAmount >= dustThreshold else {
            throw error("Amount is below \(chainName) dust threshold.")
        }
        guard feeRate >= minimumRelayFeeRate else {
            throw error("\(chainName) fee rate is below standard relay policy.")
        }
        let estimatedBytes = UInt64(spendPlan.estimatedTransactionBytes)
        guard estimatedBytes <= maxStandardTransactionBytes else {
            throw error("\(chainName) transaction is too large for standard relay policy.")
        }
        guard spendPlan.totalInputValue >= sendAmount + spendPlan.fee else {
            throw insufficientFunds
        }
        if spendPlan.usesChangeOutput, spendPlan.change < dustThreshold {
            throw error("Calculated \(chainName) change is below dust threshold.")
        }
    }
}

struct UTXOKilobyteFeePolicy {
    let chainName: String
    let baseUnitsPerCoin: Double
    let dustThreshold: UInt64
    let minimumRelayFeePerKB: Double
    let maxStandardTransactionBytes: UInt64

    func adjustedFeeRatePerKB(
        baseRate: Double,
        multiplier: Double,
        maxRate: Double? = nil
    ) -> Double {
        let adjusted = max(minimumRelayFeePerKB, baseRate * multiplier)
        guard let maxRate else { return adjusted }
        return min(adjusted, maxRate)
    }

    func estimatedFeeBaseUnits(estimatedBytes: Int, feeRatePerKB: Double) -> UInt64 {
        let kb = max(1, Int(ceil(Double(estimatedBytes) / 1_000.0)))
        let fee = Double(kb) * max(minimumRelayFeePerKB, feeRatePerKB) * baseUnitsPerCoin
        return UInt64(fee.rounded())
    }

    func preview(for totalInputValue: UInt64, inputCount: Int, feeRatePerKB: Double) -> (estimatedBytes: Int, estimatedFee: UInt64, spendable: UInt64) {
        let estimatedBytes = UTXOSpendPlanner.estimateTransactionBytes(
            inputCount: max(1, inputCount),
            outputCount: 1
        )
        let estimatedFee = estimatedFeeBaseUnits(
            estimatedBytes: estimatedBytes,
            feeRatePerKB: feeRatePerKB
        )
        let spendable = totalInputValue > estimatedFee ? totalInputValue - estimatedFee : 0
        return (estimatedBytes, estimatedFee, spendable)
    }

    func validatePlan<T>(
        sendAmount: UInt64,
        spendPlan: UTXOSpendPlan<T>,
        feeRatePerKB: Double,
        error: (String) -> Error,
        insufficientFunds: Error
    ) throws {
        guard sendAmount >= dustThreshold else {
            throw error("Amount is below \(chainName) dust threshold.")
        }
        guard feeRatePerKB >= minimumRelayFeePerKB else {
            throw error("\(chainName) fee rate is below standard relay policy.")
        }
        let estimatedBytes = UInt64(spendPlan.estimatedTransactionBytes)
        guard estimatedBytes <= maxStandardTransactionBytes else {
            throw error("\(chainName) transaction is too large for standard relay policy.")
        }
        guard spendPlan.totalInputValue >= sendAmount + spendPlan.fee else {
            throw insufficientFunds
        }
        if spendPlan.usesChangeOutput, spendPlan.change < dustThreshold {
            throw error("Calculated \(chainName) change is below dust threshold.")
        }
    }
}

enum UTXOFeePriorityMultiplierPolicy {
    static func multiplier(for priority: DogecoinWalletEngine.FeePriority) -> Double {
        switch priority {
        case .economy:
            return 0.9
        case .normal:
            return 1.0
        case .priority:
            return 1.25
        }
    }
}
