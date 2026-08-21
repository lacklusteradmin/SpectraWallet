import Foundation

// The shared staking types are emitted from `core/src/staking/types.rs` via
// UniFFI (`StakingActionKind`, `StakingValidator`, `StakingPosition`,
// `StakingActionPreview`, `StakingError`). This file adds Swift-side
// presentation helpers on top.

extension StakingActionKind: CaseIterable, Identifiable {
    public static var allCases: [StakingActionKind] {
        [.stake, .unstake, .withdraw, .restake, .claimRewards, .changeValidator]
    }
    public var id: String { String(describing: self) }
    var displayName: String {
        switch self {
        case .stake: return AppLocalization.string("Stake")
        case .unstake: return AppLocalization.string("Unstake")
        case .withdraw: return AppLocalization.string("Withdraw")
        case .restake: return AppLocalization.string("Restake")
        case .claimRewards: return AppLocalization.string("Claim Rewards")
        case .changeValidator: return AppLocalization.string("Change Validator")
        }
    }
    var systemIconName: String {
        switch self {
        case .stake: return "arrow.up.right.circle.fill"
        case .unstake: return "arrow.down.left.circle.fill"
        case .withdraw: return "arrow.down.to.line.circle.fill"
        case .restake: return "arrow.triangle.2.circlepath.circle.fill"
        case .claimRewards: return "gift.circle.fill"
        case .changeValidator: return "arrow.left.arrow.right.circle.fill"
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
