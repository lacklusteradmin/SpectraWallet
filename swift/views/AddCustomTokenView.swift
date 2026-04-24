import Foundation
import SwiftUI
struct AddCustomTokenView: View {
    let store: AppState
    @State private var selectedChain: TokenTrackingChain = .ethereum
    @State private var symbolInput: String = ""
    @State private var nameInput: String = ""
    @State private var contractInput: String = ""
    @State private var coinGeckoIdInput: String = ""
    @State private var decimalsInput: Int = 6
    @State private var formMessage: String?
    var body: some View {
        Form {
            Section {
                Text(
                    AppLocalization.string(
                        "Add a custom token contract, mint address, coin type, package address, account ID, or jetton master address for Ethereum, Arbitrum, Optimism, BNB Chain, Avalanche, Hyperliquid, Solana, Sui, Aptos, TON, NEAR, or Tron."
                    )
                ).font(.caption).foregroundStyle(.secondary)
            }
            Section(AppLocalization.string("Token Details")) {
                Picker(AppLocalization.string("Chain"), selection: $selectedChain) {
                    ForEach(TokenTrackingChain.allCases) { chain in Text(chain.rawValue).tag(chain) }
                }
                TextField(AppLocalization.string("Symbol"), text: $symbolInput).textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                TextField(AppLocalization.string("Name"), text: $nameInput)
                TextField(selectedChain.contractAddressPrompt, text: $contractInput).textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Stepper(AppLocalization.format("Token Supports: %lld decimals", decimalsInput), value: $decimalsInput, in: 0...30, step: 1)
                TextField(AppLocalization.string("CoinGecko ID (Optional)"), text: $coinGeckoIdInput).textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section {
                if let formMessage { Text(formMessage).font(.caption).foregroundStyle(.secondary) }
                Button(AppLocalization.string("Add Token")) {
                    let message = store.addCustomTokenPreference(
                        chain: selectedChain, symbol: symbolInput, name: nameInput, contractAddress: contractInput,
                        coinGeckoId: coinGeckoIdInput, decimals: decimalsInput
                    )
                    if let message {
                        formMessage = message
                    } else {
                        formMessage = AppLocalization.string("Token added.")
                        symbolInput = ""
                        nameInput = ""
                        contractInput = ""
                        coinGeckoIdInput = ""
                    }
                }
            }
        }.navigationTitle(AppLocalization.string("New Token"))
    }
}
