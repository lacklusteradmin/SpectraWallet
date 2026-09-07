import Foundation
import SwiftUI

struct BuyCryptoHelpView: View {
    private var copy: SettingsContentCopy { .current }

    /// Resolved once for the process, not once per `body`.
    ///
    /// The rows used to be built in a stored property whose element `id` was a
    /// fresh `UUID()`. `SettingsView` holds `@Bindable var store`, so its body
    /// re-evaluates on every balance and price change and rebuilt this view —
    /// which minted new identities, and `ForEach` replaced every row mid-tap.
    /// A `Link` cannot fire if the row under the finger is torn down first.
    private static let directory = BuyProviders.current

    private func section(_ title: String, _ note: String, _ providers: [BuyProviderSeed]) -> some View {
        Section {
            Text(note).font(.caption).foregroundStyle(.secondary)
            ForEach(providers) { provider in
                if let url = URL(string: provider.url) {
                    Link(destination: url) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.name).font(.body)
                                Text(provider.label)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 12)
                            Image(systemName: "arrow.up.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text(title)
        }
    }

    var body: some View {
        Form {
            Section {
                Text(copy.buyProvidersIntro).font(.caption).foregroundStyle(.secondary)
            }
            section(
                AppLocalization.string("On-ramps"), copy.buyOnrampNote, Self.directory.onramps)
            section(
                AppLocalization.string("Exchanges"), copy.buyExchangeNote, Self.directory.exchanges)
            Section(AppLocalization.string("Reminder")) {
                Text(copy.buyWarning).font(.caption).foregroundStyle(.secondary)
                Text(copy.buyListingNote).font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(AppLocalization.string("Where can I buy crypto?"))
    }
}
