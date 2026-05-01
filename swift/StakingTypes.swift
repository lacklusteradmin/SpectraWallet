import Foundation

// The shared staking types are emitted from `core/src/staking/types.rs` via
// UniFFI (`StakingActionKind`, `StakingValidator`, `StakingPosition`,
// `StakingActionPreview`, `StakingError`). This file adds Swift-side
// presentation helpers on top.

extension StakingActionKind: CaseIterable, Identifiable {
    public static var allCases: [StakingActionKind] {
        [.stake, .unstake, .withdraw, .restake, .claimRewards]
    }
    public var id: String { String(describing: self) }
    var displayName: String {
        switch self {
        case .stake: return AppLocalization.string("Stake")
        case .unstake: return AppLocalization.string("Unstake")
        case .withdraw: return AppLocalization.string("Withdraw")
        case .restake: return AppLocalization.string("Restake")
        case .claimRewards: return AppLocalization.string("Claim Rewards")
        }
    }
    var systemIconName: String {
        switch self {
        case .stake: return "arrow.up.right.circle.fill"
        case .unstake: return "arrow.down.left.circle.fill"
        case .withdraw: return "arrow.down.to.line.circle.fill"
        case .restake: return "arrow.triangle.2.circlepath.circle.fill"
        case .claimRewards: return "gift.circle.fill"
        }
    }
}

extension StakingPositionStatus {
    var displayName: String {
        switch self {
        case .active: return AppLocalization.string("Active")
        case .activating: return AppLocalization.string("Activating")
        case .unbonding: return AppLocalization.string("Unbonding")
        case .withdrawable: return AppLocalization.string("Withdrawable")
        case .inactive: return AppLocalization.string("Inactive")
        }
    }
}

/// Canonical list of chains that expose protocol-native staking. Drives the
/// staking tab's chain picker and conditional UI surfaces.
enum StakingSupportedChain: String, CaseIterable, Identifiable {
    case solana
    case cardano
    case sui
    case aptos
    case near
    case polkadot
    case icp
    var id: String { rawValue }
    var chainName: String {
        switch self {
        case .solana: return "Solana"
        case .cardano: return "Cardano"
        case .sui: return "Sui"
        case .aptos: return "Aptos"
        case .near: return "NEAR"
        case .polkadot: return "Polkadot"
        case .icp: return "Internet Computer"
        }
    }
}
