import Foundation

extension AppState {
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
            return AppLocalization.string("This token could not be saved.")
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
        case .unknownChain: return AppLocalization.string("That network cannot hold tokens.")
        case .emptySymbol: return AppLocalization.string("Symbol is required.")
        case .symbolTooLong: return AppLocalization.string("Symbol is too long.")
        case .invalidPriceId: return AppLocalization.string("Enter a price provider ID, not a URL or name.")
        case .emptyName: return AppLocalization.string("Token name is required.")
        case .emptyContract: return AppLocalization.string("Token identifier is required.")
        case .invalidContract: return AppLocalization.string("That token identifier is not valid for this network.")
        case .duplicateToken: return AppLocalization.string("This network already knows this token.")
        case .tooManyDecimals: return AppLocalization.string("That is more decimal places than a token has.")
        case .builtInToken: return AppLocalization.string("Built-in tokens cannot be edited or removed.")
        case .unknownToken: return AppLocalization.string("That token is no longer in the list.")
        }
    }
    /// Teach the wallet a token the catalog does not ship.
    ///
    /// Returns the refusal to show beside the form, or `nil` once core has
    /// accepted it. Every rule behind that answer — the symbol, the contract's
    /// format for the chain that would host it, the duplicate, the precision,
    /// and where the row sorts — is the reducer's.
    func addCustomTokenPreference(
        chain: Chain, symbol: String, name: String, contractAddress: String,
        coingeckoId: String = "", coinpaprikaId: String = "", decimals: UInt32, editing: TokenPreferenceEntry? = nil
    ) async -> String? {
        let command: StateCommand
        if let editing {
            command = .updateCustomToken(
                chainId: editing.token.chainId,
                contract: editing.token.contract, symbol: symbol, name: name,
                coingeckoId: coingeckoId, coinpaprikaId: coinpaprikaId, decimals: decimals)
        } else {
            command = .addCustomToken(
                chainId: chain, symbol: symbol, name: name,
                contract: contractAddress, coingeckoId: coingeckoId,
                coinpaprikaId: coinpaprikaId, decimals: decimals)
        }
        let result: Result<StateTransition, Error>
        do { result = .success(try await applyStateCommand(command)) } catch { result = .failure(error) }
        tokenPreferenceError = tokenPreferenceErrorMessage(result)
        return tokenPreferenceError
    }
}
