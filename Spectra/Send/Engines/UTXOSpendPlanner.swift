import Foundation

struct UTXOSpendPlan<UTXO> {
    let utxos: [UTXO]
    let totalInputValue: UInt64
    let fee: UInt64
    let change: UInt64
    let usesChangeOutput: Bool
    let estimatedTransactionBytes: Int
}

enum UTXOSpendPlanner {
    static func estimateTransactionBytes(
        inputCount: Int,
        outputCount: Int,
        inputBytes: Int = 148,
        outputBytes: Int = 34,
        overheadBytes: Int = 10
    ) -> Int {
        overheadBytes + (inputBytes * inputCount) + (outputBytes * outputCount)
    }

    static func buildPlan<UTXO>(
        from utxos: [UTXO],
        targetValue: UInt64,
        dustThreshold: UInt64,
        maxInputCount: Int?,
        sortBy: (UTXO, UTXO) -> Bool,
        value: (UTXO) -> UInt64,
        feeForLayout: (Int, Int) -> UInt64
    ) -> UTXOSpendPlan<UTXO>? {
        guard !utxos.isEmpty else { return nil }

        let sortedUTXOs = utxos.sorted(by: sortBy)
        let effectiveMaxInputCount = maxInputCount.map { max(1, $0) }
        var candidates: [[UTXO]] = []
        candidates.reserveCapacity(sortedUTXOs.count * 2)

        var prefix: [UTXO] = []
        prefix.reserveCapacity(sortedUTXOs.count)
        for utxo in sortedUTXOs {
            prefix.append(utxo)
            if let effectiveMaxInputCount, prefix.count > effectiveMaxInputCount {
                continue
            }
            candidates.append(prefix)
        }

        for utxo in sortedUTXOs {
            candidates.append([utxo])
        }

        var bestPlan: UTXOSpendPlan<UTXO>?
        for candidate in candidates {
            guard let plan = evaluateCandidate(
                candidate,
                targetValue: targetValue,
                dustThreshold: dustThreshold,
                value: value,
                feeForLayout: feeForLayout
            ) else {
                continue
            }

            if let currentBest = bestPlan {
                if isBetterPlan(plan, than: currentBest) {
                    bestPlan = plan
                }
            } else {
                bestPlan = plan
            }
        }

        return bestPlan
    }

    private static func evaluateCandidate<UTXO>(
        _ utxos: [UTXO],
        targetValue: UInt64,
        dustThreshold: UInt64,
        value: (UTXO) -> UInt64,
        feeForLayout: (Int, Int) -> UInt64
    ) -> UTXOSpendPlan<UTXO>? {
        guard !utxos.isEmpty else { return nil }

        let totalInputValue = utxos.reduce(UInt64(0)) { partialResult, utxo in
            partialResult + value(utxo)
        }

        let feeWithChange = feeForLayout(utxos.count, 2)
        if totalInputValue >= targetValue + feeWithChange {
            let changeWithChange = totalInputValue - targetValue - feeWithChange
            if changeWithChange >= dustThreshold {
                return UTXOSpendPlan(
                    utxos: utxos,
                    totalInputValue: totalInputValue,
                    fee: feeWithChange,
                    change: changeWithChange,
                    usesChangeOutput: true,
                    estimatedTransactionBytes: estimateTransactionBytes(inputCount: utxos.count, outputCount: 2)
                )
            }
        }

        let feeWithoutChange = feeForLayout(utxos.count, 1)
        guard totalInputValue >= targetValue + feeWithoutChange else {
            return nil
        }

        let remainder = totalInputValue - targetValue - feeWithoutChange
        return UTXOSpendPlan(
            utxos: utxos,
            totalInputValue: totalInputValue,
            fee: feeWithoutChange + remainder,
            change: 0,
            usesChangeOutput: false,
            estimatedTransactionBytes: estimateTransactionBytes(inputCount: utxos.count, outputCount: 1)
        )
    }

    private static func isBetterPlan<UTXO>(
        _ lhs: UTXOSpendPlan<UTXO>,
        than rhs: UTXOSpendPlan<UTXO>
    ) -> Bool {
        if lhs.usesChangeOutput != rhs.usesChangeOutput {
            return lhs.usesChangeOutput && !rhs.usesChangeOutput
        }
        if lhs.utxos.count != rhs.utxos.count {
            return lhs.utxos.count < rhs.utxos.count
        }
        if lhs.fee != rhs.fee {
            return lhs.fee < rhs.fee
        }
        return lhs.change < rhs.change
    }
}
