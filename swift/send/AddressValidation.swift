import Foundation
enum AddressValidation {
    nonisolated static func isValidBitcoinAddress(_ address: String, networkMode: BitcoinNetworkMode) -> Bool { validateAddress(kind: "bitcoin", value: address, networkMode: networkMode.rawValue).isValid }
    nonisolated static func isValidBitcoinCashAddress(_ address: String) -> Bool { validateAddress(kind: "bitcoinCash", value: address).isValid }
    nonisolated static func isValidBitcoinSVAddress(_ address: String) -> Bool { validateAddress(kind: "bitcoinSV", value: address).isValid }
    nonisolated static func isValidLitecoinAddress(_ address: String) -> Bool { validateAddress(kind: "litecoin", value: address).isValid }
    nonisolated static func isValidDogecoinAddress(_ address: String, networkMode: DogecoinNetworkMode = .mainnet) -> Bool { validateAddress(kind: "dogecoin", value: address, networkMode: networkMode.rawValue).isValid }
    nonisolated static func isValidEthereumAddress(_ address: String) -> Bool { validateAddress(kind: "evm", value: address).isValid }
    nonisolated static func isValidTronAddress(_ address: String) -> Bool { validateAddress(kind: "tron", value: address).isValid }
    nonisolated static func isValidSolanaAddress(_ address: String) -> Bool { validateAddress(kind: "solana", value: address).isValid }
    nonisolated static func isValidStellarAddress(_ address: String) -> Bool { validateAddress(kind: "stellar", value: address).isValid }
    nonisolated static func isValidXRPAddress(_ address: String) -> Bool { validateAddress(kind: "xrp", value: address).isValid }
    nonisolated static func isValidSuiAddress(_ address: String) -> Bool { validateAddress(kind: "sui", value: address).isValid }
    nonisolated static func isValidAptosAddress(_ address: String) -> Bool { validateAddress(kind: "aptos", value: address).isValid }
    nonisolated static func isValidTONAddress(_ address: String) -> Bool { validateAddress(kind: "ton", value: address).isValid }
    nonisolated static func isValidAptosTokenType(_ value: String) -> Bool {
        coreValidateStringIdentifier(request: StringValidationRequest(kind: "aptosTokenType", value: value)).isValid
    }
    nonisolated static func isValidICPAddress(_ address: String) -> Bool { validateAddress(kind: "internetComputer", value: address).isValid }
    nonisolated static func isValidNearAddress(_ address: String) -> Bool { validateAddress(kind: "near", value: address).isValid }
    nonisolated static func isValidPolkadotAddress(_ address: String) -> Bool { validateAddress(kind: "polkadot", value: address).isValid }
    nonisolated static func isValidMoneroAddress(_ address: String) -> Bool { validateAddress(kind: "monero", value: address).isValid }
    nonisolated static func isValidCardanoAddress(_ address: String) -> Bool { validateAddress(kind: "cardano", value: address).isValid }
    nonisolated static func normalizedBitcoinAddress(_ address: String, networkMode: BitcoinNetworkMode) -> String? { validateAddress(kind: "bitcoin", value: address, networkMode: networkMode.rawValue).normalizedValue }
    nonisolated static func normalizedDogecoinAddress(_ address: String, networkMode: DogecoinNetworkMode = .mainnet) -> String? { validateAddress(kind: "dogecoin", value: address, networkMode: networkMode.rawValue).normalizedValue }
    nonisolated static func normalizedEthereumAddress(_ address: String) -> String? { validateAddress(kind: "evm", value: address).normalizedValue }
    nonisolated static func normalizedSuiAddress(_ address: String) -> String? { validateAddress(kind: "sui", value: address).normalizedValue }
    nonisolated static func normalizedAptosAddress(_ address: String) -> String? { validateAddress(kind: "aptos", value: address).normalizedValue }
    nonisolated static func normalizedTONAddress(_ address: String) -> String? { validateAddress(kind: "ton", value: address).normalizedValue }
    nonisolated static func normalizedICPAddress(_ address: String) -> String? { validateAddress(kind: "internetComputer", value: address).normalizedValue }
    nonisolated static func normalizedNearAddress(_ address: String) -> String? { validateAddress(kind: "near", value: address).normalizedValue }
    private nonisolated static func validateAddress(kind: String, value: String, networkMode: String? = nil) -> AddressValidationResult {
        coreValidateAddress(request: AddressValidationRequest(kind: kind, value: value, networkMode: networkMode))
    }
}
