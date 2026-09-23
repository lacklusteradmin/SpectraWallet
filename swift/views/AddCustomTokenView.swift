import Foundation
import SwiftUI

struct AddCustomTokenView: View {
    let store: AppState
    var editing: TokenPreferenceEntry? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var selectedChain: TokenHostingChain = .ethereum
    @State private var symbolInput = ""
    @State private var nameInput = ""
    @State private var identifierInput = ""
    @State private var coingeckoIdInput = ""
    @State private var coinpaprikaIdInput = ""
    @State private var decimalsInput = 6
    @State private var formMessage: String?
    @State private var isSaving = false
    @State private var hasLoaded = false

    var body: some View {
        Form {
            Section(AppLocalization.string("Network")) {
                if let editing {
                    LabeledContent(AppLocalization.string("Network"), value: selectedChain.rawValue)
                    Text(editing.token.contract).font(.caption.monospaced()).textSelection(.enabled)
                } else {
                    Picker(AppLocalization.string("Network"), selection: $selectedChain) {
                        ForEach(TokenHostingChain.allCases) { chain in Text(chain.rawValue).tag(chain) }
                    }
                    TextField(AppLocalization.string("Token Identifier"), text: $identifierInput)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            }
            Section(AppLocalization.string("Token Details")) {
                TextField(AppLocalization.string("Name"), text: $nameInput)
                TextField(AppLocalization.string("Symbol"), text: $symbolInput)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                Stepper(AppLocalization.format("Token Supports: %lld decimals", decimalsInput), value: $decimalsInput, in: 0...30)
            }
            Section {
                TextField(AppLocalization.string("CoinGecko ID (Optional)"), text: $coingeckoIdInput)
                TextField(AppLocalization.string("CoinPaprika ID (Optional)"), text: $coinpaprikaIdInput)
            } header: {
                Text(AppLocalization.string("Price Sources"))
            } footer: {
                Text(AppLocalization.string("Both price sources are optional. Use the provider's token ID, not its website URL."))
            }.textInputAutocapitalization(.never).autocorrectionDisabled()
            if let formMessage {
                Section { Text(formMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle(AppLocalization.string(editing == nil ? "New Token" : "Edit Token"))
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isSaving)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(AppLocalization.string("Save")) {
                    isSaving = true
                    Task { @MainActor in
                        formMessage = await store.addCustomTokenPreference(
                            chain: selectedChain, symbol: symbolInput, name: nameInput,
                            contractAddress: identifierInput, coingeckoId: coingeckoIdInput,
                            coinpaprikaId: coinpaprikaIdInput, decimals: decimalsInput, editing: editing)
                        isSaving = false
                        if formMessage == nil { dismiss() }
                    }
                }.disabled(isSaving)
            }
        }
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            guard let editing else { return }
            selectedChain = editing.hostingChain ?? .ethereum
            symbolInput = editing.token.symbol
            nameInput = editing.token.name
            identifierInput = editing.token.contract
            coingeckoIdInput = editing.token.coingeckoId
            coinpaprikaIdInput = editing.token.coinpaprikaId
            decimalsInput = Int(editing.token.decimals)
        }
    }
}
