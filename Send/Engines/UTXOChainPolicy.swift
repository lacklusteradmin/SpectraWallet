import Foundation

struct UTXOKilobyteFeePolicy {
    let baseUnitsPerCoin: Double
    let dustThreshold: UInt64
    let minimumRelayFeePerKB: Double

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
}

enum UTXOFeePriorityMultiplierPolicy {
    static func multiplier(for priority: DogecoinFeePriority) -> Double {
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
