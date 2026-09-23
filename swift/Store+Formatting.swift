import Foundation

// Localized display messages. AmountPresentation owns native number rendering.

func localizedStoreString(_ key: String) -> String {
    AppLocalization.string(key)
}

/// Every recipient warning, worded. Exhaustive: a reason core adds does not
/// compile until it has words, where a `default` returning nothing dropped it
/// from the confirmation sheet.
func evmRecipientMessages(_ warnings: [EvmRecipientPreflightWarning]) -> [String] {
    warnings.map { warning in
        switch warning {
        case .recipientIsContract(let chainName, let symbol):
            return AppLocalization.format(
                "Recipient is a smart contract on %@. Confirm it can receive %@ safely.", chainName, symbol)
        case .recipientCodeUnknown(let chainName):
            return AppLocalization.format(
                "Could not verify recipient contract state on %@. Review destination carefully.", chainName)
        case .tokenContractMissing(let chainName, let tokenSymbol):
            return AppLocalization.format(
                "Token contract %@ appears missing on %@. This may be a wrong-network token selection.",
                tokenSymbol, chainName)
        case .tokenCodeUnknown(let chainName, let tokenSymbol):
            return AppLocalization.format("Could not verify %@ contract bytecode on %@.", tokenSymbol, chainName)
        }
    }
}
/// Every reason a send looks risky, worded. Exhaustive for the same reason as
/// `evmRecipientMessages`.
func highRiskSendMessages(_ warnings: [HighRiskSendWarning]) -> [String] {
    warnings.map { warning in
        switch warning {
        case .invalidFormat(let chain):
            return AppLocalization.format("The destination address format does not match %@.", chain)
        case .newAddress:
            return localizedStoreString("This is a new destination address with no prior history in this wallet.")
        case .ensResolved(let name, let address):
            return AppLocalization.format(
                "ENS name '%@' resolved to %@. Confirm this resolved address before sending.", name, address)
        case .largeSend(let percent, let symbol):
            let formatted = (Double(percent) / 100.0).formatted(.percent.precision(.fractionLength(0)))
            return AppLocalization.format("This send is %@ of your %@ balance.", formatted, symbol)
        case .nonEvmOnEvm(let chain):
            return AppLocalization.format("Destination appears to be a non-EVM address while sending on %@.", chain)
        case .ensOffEthereum(let chain):
            return AppLocalization.format(
                "ENS names are Ethereum-specific. For %@, verify the resolved EVM address very carefully.", chain)
        case .ethOnUtxo(let chain):
            return AppLocalization.format("Destination appears to be an Ethereum-style address while sending on %@.", chain)
        case .foreignAddressFormat(let chain):
            return AppLocalization.format("Destination appears to be another network's address format while sending on %@.", chain)
        case .chainMismatch:
            return localizedStoreString("Wallet-chain context mismatch detected for this send.")
        }
    }
}

/// Localized title and message for a destination verdict.
func chainRiskProbeMessages(chainName: String, symbol: String, activity: SendDestinationActivity) -> (
    warning: String?, info: String?
) {
    switch activity {
    case .unused:
        return (AppLocalization.format(
            "Warning: this %@ address has zero %@ balance and no transaction history. Double-check recipient details.",
            chainName, symbol), nil)
    case .emptyPreviouslyUsed:
        return (nil, AppLocalization.format(
            "Note: this %@ address has transaction history but currently zero %@ balance.", chainName, symbol))
    case .funded: return (nil, nil)
    }
}
