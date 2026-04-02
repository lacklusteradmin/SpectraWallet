import SwiftUI

struct DashboardAssetRowPresentation: Identifiable {
    let assetGroup: DashboardAssetGroup
    let amountText: String
    let totalValueText: String
    let priceText: String
    let chainSummaryText: String

    var id: String { assetGroup.id }
}

@ViewBuilder
func dashboardDetailRow(label: String, value: String) -> some View {
    HStack(alignment: .top) {
        Text(label)
            .foregroundStyle(.secondary)
        Spacer(minLength: 16)
        Text(value)
            .multilineTextAlignment(.trailing)
    }
    .font(.caption)
}

struct DashboardAssetRowView: View {
    let presentation: DashboardAssetRowPresentation

    var body: some View {
        HStack(spacing: 14) {
            CoinBadge(
                assetIdentifier: presentation.assetGroup.iconIdentifier,
                fallbackText: presentation.assetGroup.mark,
                color: presentation.assetGroup.color,
                size: 40
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if presentation.assetGroup.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.red.opacity(0.82))
                            .frame(width: 28, height: 20)
                            .background(Color.red.opacity(0.1), in: Capsule())
                            .clipped()
                    }
                    Text(presentation.assetGroup.name)
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Text(presentation.amountText)
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.72))
                    .spectraNumericTextLayout()

                Text(presentation.chainSummaryText)
                    .font(.caption2)
                    .foregroundStyle(Color.primary.opacity(0.58))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(presentation.totalValueText)
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .spectraNumericTextLayout()
                Text(presentation.priceText)
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.68))
                    .spectraNumericTextLayout()
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.42))
        }
        .padding(16)
        .spectraBubbleFill()
        .glassEffect(.regular.tint(.white.opacity(0.025)), in: .rect(cornerRadius: 24))
    }
}

struct DashboardPinnedAssetRowView: View {
    let option: DashboardPinOption
    let subtitleText: String

    var body: some View {
        HStack(spacing: 12) {
            CoinBadge(
                assetIdentifier: option.assetIdentifier,
                fallbackText: option.mark,
                color: option.color,
                size: 34
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(option.name)
                Text(subtitleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PortfolioWalletToggleRowView: View {
    @EnvironmentObject private var store: WalletStore
    let wallet: ImportedWallet

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(wallet.name)
            Text(store.displayNetworkName(for: wallet.selectedChain))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct DashboardNoticeCardView: View {
    let notice: AppNoticeItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: notice.systemImage)
                    .foregroundStyle(notice.severity.tint)
                Text(notice.title)
                    .font(.headline)
                Spacer()
                Text(notice.severity.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(notice.severity.tint)
            }

            Text(notice.message)
                .font(.subheadline)
                .foregroundStyle(.primary)

            if let timestamp = notice.timestamp {
                Text(dashboardComponentsLocalizedFormat("Last known healthy sync: %@", timestamp.formatted(date: .abbreviated, time: .shortened)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private func dashboardComponentsLocalizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    let format = NSLocalizedString(key, comment: "")
    return String(format: format, locale: Locale.current, arguments: arguments)
}
