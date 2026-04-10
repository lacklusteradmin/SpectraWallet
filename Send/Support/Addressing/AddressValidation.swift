import Foundation

private struct RustAddressValidationPayload: Encodable {
    let kind: String
    let value: String
    let networkMode: String?
}

private struct RustStringValidationPayload: Encodable {
    let kind: String
    let value: String
}

private struct RustAddressValidationResponse: Decodable {
    let isValid: Bool
    let normalizedValue: String?
}

private struct RustStringValidationResponse: Decodable {
    let isValid: Bool
    let normalizedValue: String?
}

enum AddressValidation {
    nonisolated static func isValidBitcoinAddress(_ address: String, networkMode: BitcoinNetworkMode) -> Bool {
        validateAddress(
            kind: "bitcoin",
            value: address,
            networkMode: networkMode.rawValue
        )?.isValid == true
    }

    nonisolated static func isValidBitcoinCashAddress(_ address: String) -> Bool {
        validateAddress(kind: "bitcoinCash", value: address)?.isValid == true
    }

    nonisolated static func isValidBitcoinSVAddress(_ address: String) -> Bool {
        validateAddress(kind: "bitcoinSV", value: address)?.isValid == true
    }

    nonisolated static func isValidLitecoinAddress(_ address: String) -> Bool {
        validateAddress(kind: "litecoin", value: address)?.isValid == true
    }

    nonisolated static func isValidDogecoinAddress(
        _ address: String,
        networkMode: DogecoinNetworkMode = .mainnet
    ) -> Bool {
        validateAddress(
            kind: "dogecoin",
            value: address,
            networkMode: networkMode.rawValue
        )?.isValid == true
    }

    nonisolated static func isValidEthereumAddress(_ address: String) -> Bool {
        validateAddress(kind: "evm", value: address)?.isValid == true
    }

    nonisolated static func isValidTronAddress(_ address: String) -> Bool {
        validateAddress(kind: "tron", value: address)?.isValid == true
    }

    nonisolated static func isValidSolanaAddress(_ address: String) -> Bool {
        validateAddress(kind: "solana", value: address)?.isValid == true
    }

    nonisolated static func isValidStellarAddress(_ address: String) -> Bool {
        validateAddress(kind: "stellar", value: address)?.isValid == true
    }

    nonisolated static func isValidXRPAddress(_ address: String) -> Bool {
        validateAddress(kind: "xrp", value: address)?.isValid == true
    }

    nonisolated static func isValidSuiAddress(_ address: String) -> Bool {
        validateAddress(kind: "sui", value: address)?.isValid == true
    }

    nonisolated static func isValidAptosAddress(_ address: String) -> Bool {
        validateAddress(kind: "aptos", value: address)?.isValid == true
    }

    nonisolated static func isValidTONAddress(_ address: String) -> Bool {
        validateAddress(kind: "ton", value: address)?.isValid == true
    }

    nonisolated static func isValidAptosTokenType(_ value: String) -> Bool {
        validateStringIdentifier(kind: "aptosTokenType", value: value)?.isValid == true
    }

    nonisolated static func isValidICPAddress(_ address: String) -> Bool {
        validateAddress(kind: "internetComputer", value: address)?.isValid == true
    }

    nonisolated static func isValidNearAddress(_ address: String) -> Bool {
        validateAddress(kind: "near", value: address)?.isValid == true
    }

    nonisolated static func isValidPolkadotAddress(_ address: String) -> Bool {
        validateAddress(kind: "polkadot", value: address)?.isValid == true
    }

    nonisolated static func isValidMoneroAddress(_ address: String) -> Bool {
        validateAddress(kind: "monero", value: address)?.isValid == true
    }

    nonisolated static func isValidCardanoAddress(_ address: String) -> Bool {
        validateAddress(kind: "cardano", value: address)?.isValid == true
    }

    nonisolated static func normalizedBitcoinAddress(
        _ address: String,
        networkMode: BitcoinNetworkMode
    ) -> String? {
        validateAddress(kind: "bitcoin", value: address, networkMode: networkMode.rawValue)?.normalizedValue
    }

    nonisolated static func normalizedDogecoinAddress(
        _ address: String,
        networkMode: DogecoinNetworkMode = .mainnet
    ) -> String? {
        validateAddress(kind: "dogecoin", value: address, networkMode: networkMode.rawValue)?.normalizedValue
    }

    nonisolated static func normalizedEthereumAddress(_ address: String) -> String? {
        validateAddress(kind: "evm", value: address)?.normalizedValue
    }

    nonisolated static func normalizedSuiAddress(_ address: String) -> String? {
        validateAddress(kind: "sui", value: address)?.normalizedValue
    }

    nonisolated static func normalizedAptosAddress(_ address: String) -> String? {
        validateAddress(kind: "aptos", value: address)?.normalizedValue
    }

    nonisolated static func normalizedTONAddress(_ address: String) -> String? {
        validateAddress(kind: "ton", value: address)?.normalizedValue
    }

    nonisolated static func normalizedICPAddress(_ address: String) -> String? {
        validateAddress(kind: "internetComputer", value: address)?.normalizedValue
    }

    nonisolated static func normalizedNearAddress(_ address: String) -> String? {
        validateAddress(kind: "near", value: address)?.normalizedValue
    }

    private nonisolated static func validateAddress(
        kind: String,
        value: String,
        networkMode: String? = nil
    ) -> RustAddressValidationResponse? {
        MainActor.assumeIsolated {
            let payload = RustAddressValidationPayload(kind: kind, value: value, networkMode: networkMode)
            guard let json = try? encodeJSONString(payload),
                  let responseJSON = try? coreValidateAddressJson(requestJson: json),
                  let data = responseJSON.data(using: .utf8),
                  let response = try? JSONDecoder().decode(RustAddressValidationResponse.self, from: data) else {
                return nil
            }
            return response
        }
    }

    private nonisolated static func validateStringIdentifier(
        kind: String,
        value: String
    ) -> RustStringValidationResponse? {
        MainActor.assumeIsolated {
            let payload = RustStringValidationPayload(kind: kind, value: value)
            guard let json = try? encodeJSONString(payload),
                  let responseJSON = try? coreValidateStringIdentifierJson(requestJson: json),
                  let data = responseJSON.data(using: .utf8),
                  let response = try? JSONDecoder().decode(RustStringValidationResponse.self, from: data) else {
                return nil
            }
            return response
        }
    }

    private nonisolated static func encodeJSONString<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return json
    }
}
