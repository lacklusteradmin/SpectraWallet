import Foundation

@MainActor
extension AppState {
    /// A token is addressed by what it is — its contract on its chain.
    private func tokenKey(_ entry: TokenPreferenceEntry) -> CoreTokenPreferenceKey {
        CoreTokenPreferenceKey(chainId: entry.token.chainId, contract: entry.token.contract)
    }
    func setTokenPreferenceEnabled(_ entry: TokenPreferenceEntry, isEnabled: Bool) {
        setTokenPreferencesEnabled([entry], isEnabled: isEnabled)
    }
    func setTokenPreferencesEnabled(_ entries: [TokenPreferenceEntry], isEnabled: Bool) {
        let keys = entries.map(tokenKey)
        guard !keys.isEmpty else { return }
        sendTokenPreferenceCommand(.setTokenPreferencesEnabled(tokens: keys, isEnabled: isEnabled))
    }
    func removeCustomTokenPreference(_ entry: TokenPreferenceEntry) {
        sendTokenPreferenceCommand(.removeCustomToken(chainId: entry.token.chainId, contract: entry.token.contract))
    }
    /// Send a token-preference command. Same shape as `sendAddressBookCommand`:
    /// core decides, the refusal comes back as an event carrying its reason,
    /// and this side supplies the words.
    private func sendTokenPreferenceCommand(_ command: StateCommand) {
        enqueueStateCommand(command) { store, result in
            store.tokenPreferenceError = store.tokenPreferenceErrorMessage(result)
        }
    }
    /// The words for a token command's outcome, or `nil` when core accepted it.
    private func tokenPreferenceErrorMessage(_ result: Result<StateTransition, Error>) -> String? {
        switch result {
        case .success(let transition):
            return tokenPreferenceRejection(in: transition.events).map(tokenPreferenceRejectionMessage)
        case .failure:
            return localizedStoreString("This token could not be saved.")
        }
    }
    private func tokenPreferenceRejection(in events: [StateEvent]) -> TokenPreferenceRejection? {
        events.lazy.compactMap { event -> TokenPreferenceRejection? in
            guard case .tokenPreferenceRejected(let reason) = event else { return nil }
            return reason
        }.first
    }
    func tokenPreferenceRejectionMessage(_ reason: TokenPreferenceRejection) -> String {
        switch reason {
        case .unknownChain: return localizedStoreString("That network cannot hold tokens.")
        case .emptySymbol: return localizedStoreString("Symbol is required.")
        case .symbolTooLong: return localizedStoreString("Symbol is too long.")
        case .invalidPriceId: return localizedStoreString("Enter a price provider ID, not a URL or name.")
        case .emptyName: return localizedStoreString("Token name is required.")
        case .emptyContract: return localizedStoreString("Token identifier is required.")
        case .invalidContract: return localizedStoreString("That token identifier is not valid for this network.")
        case .duplicateToken: return localizedStoreString("This network already knows this token.")
        case .tooManyDecimals: return localizedStoreString("That is more decimal places than a token has.")
        case .builtInToken: return localizedStoreString("Built-in tokens cannot be edited or removed.")
        case .unknownToken: return localizedStoreString("That token is no longer in the list.")
        }
    }
    /// Teach the wallet a token the catalog does not ship.
    ///
    /// Returns the refusal to show beside the form, or `nil` once core has
    /// accepted it. Every rule behind that answer — the symbol, the contract's
    /// format for the chain that would host it, the duplicate, the precision,
    /// and where the row sorts — is the reducer's. This method held all of
    /// them, including a seven-arm switch over the hosting chains whose
    /// `default` assumed EVM.
    func addCustomTokenPreference(
        chain: Chain, symbol: String, name: String, contractAddress: String,
        coingeckoId: String = "", coinpaprikaId: String = "", decimals: Int, editing: TokenPreferenceEntry? = nil
    ) async -> String? {
        guard decimals >= 0 else { return localizedStoreString("That is not a number of decimal places.") }

        let command: StateCommand
        if let editing {
            command = .updateCustomToken(
                chainId: editing.token.chainId,
                contract: editing.token.contract, symbol: symbol, name: name,
                coingeckoId: coingeckoId, coinpaprikaId: coinpaprikaId, decimals: UInt32(decimals))
        } else {
            command = .addCustomToken(
                chainId: chain.id, symbol: symbol, name: name,
                contract: contractAddress, coingeckoId: coingeckoId,
                coinpaprikaId: coinpaprikaId, decimals: UInt32(decimals))
        }
        let result: Result<StateTransition, Error>
        do { result = .success(try await applyStateCommand(command)) } catch { result = .failure(error) }
        tokenPreferenceError = tokenPreferenceErrorMessage(result)
        return tokenPreferenceError
    }
}
