import SwiftUI

/// Per-chain derivation paths and the passphrase and HMAC overrides for a seed
/// wallet. A sheet over the secret step rather than a page of the setup flow:
/// every field has a working default, so the linear flow never routes through
/// it and most people never open it.
struct WalletDerivationOptionsView: View {
    let store: AppState
    @Bindable var draft: WalletImportDraft
    @Environment(\.dismiss) private var dismiss
    private let copy = ImportFlowContent.current
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(
                        AppLocalization.string(
                            "Control the derivation path used for each selected chain. Pick a testnet from the chain list to use a testnet wallet."
                        )
                    ).font(.subheadline).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(draft.selectableDerivationChains) { family in
                            let chain = Chain(id: store.selectedChainId(forFamily: family.mainnetCounterpart.id)) ?? family
                            SeedPathSlotEditor(
                                title: chain.displayName,
                                path: Binding(
                                    get: { draft.seedDerivationPaths.path(for: chain) },
                                    set: { draft.seedDerivationPaths.setPath($0, for: chain) }
                                ), defaultPath: chain.defaultDerivationPath
                            )
                        }
                        PowerUserOverridesSection(draft: draft)
                    }
                }.padding(16).spectraBubbleFill().spectraCardFill().padding(20)
            }
            .navigationTitle(copy.advancedTitle).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalization.string("Done")) { dismiss() }
                }
            }
        }
    }
}

/// The passphrase and HMAC overrides, below the per-chain paths.
private struct PowerUserOverridesSection: View {
    @Bindable var draft: WalletImportDraft
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            stage1Overrides
        }.padding(14).background(
            RoundedRectangle(cornerRadius: SpectraLayout.Radius.chip, style: .continuous).fill(Color.orange.opacity(0.08))
        ).overlay(
            RoundedRectangle(cornerRadius: SpectraLayout.Radius.chip, style: .continuous).stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.bold)).foregroundStyle(.orange)
                Text(AppLocalization.string("Power-User Overrides"))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
            }
            Text(
                AppLocalization.string(
                    "Secret text is used exactly as entered, including spaces. Unsupported chain overrides are refused. Leave blank to use the chain default."
                )
            ).font(.caption).foregroundStyle(.orange.opacity(0.9))
        }
    }
    private var stage1Overrides: some View {
        VStack(alignment: .leading, spacing: 10) {
            AdvancedOverrideTextField(
                title: AppLocalization.string("Passphrase"),
                detail: AppLocalization.string("BIP-39 passphrase (“25th word”). Blank = none."),
                text: $draft.overridePassphrase, isSecure: true)
            AdvancedOverrideTextField(
                title: AppLocalization.string("HMAC Master Key"),
                detail: AppLocalization.string(
                    "Custom master HMAC key for supported chains. Blank uses the chain default."),
                text: $draft.overrideHmacKey)
        }
    }
}

private struct AdvancedOverrideTextField: View {
    let title: String
    let detail: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboard: UIKeyboardType = .default
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            inputField.font(.subheadline.monospaced()).padding(.horizontal, 10).padding(.vertical, 8)
                .spectraElevatedFill(cornerRadius: SpectraLayout.Radius.control)
                .overlay(
                    RoundedRectangle(cornerRadius: SpectraLayout.Radius.control, style: .continuous).stroke(Color.primary.opacity(0.1), lineWidth: 1))
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder
    private var inputField: some View {
        if isSecure {
            SecureField(AppLocalization.string("(default)"), text: $text)
        } else {
            TextField(AppLocalization.string("(default)"), text: $text)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(keyboard)
        }
    }
}
