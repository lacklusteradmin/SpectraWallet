import Foundation

struct ChainSelfTestResult {
    let name: String
    let passed: Bool
    let message: String
}

enum DogecoinChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] {
        [
            testAddressValidationMainnet(),
            testAddressValidationRejectsGarbage(),
            testAddressValidationRejectsChecksumMutation(),
            testSingleProviderRuntimeConfiguration()
        ]
    }

    private static func testAddressValidationMainnet() -> ChainSelfTestResult {
        let validMainnet = "DBus3bamQjgJULBJtYXpEzDWQRwF5iwxgC"
        let passed = AddressValidation.isValidDogecoinAddress(validMainnet)
        return ChainSelfTestResult(
            name: "DOGE Address Mainnet Validation",
            passed: passed,
            message: passed ? "Mainnet address accepted." : "Mainnet address validation failed."
        )
    }

    private static func testAddressValidationRejectsGarbage() -> ChainSelfTestResult {
        let passed = !AddressValidation.isValidDogecoinAddress("not_a_real_address")
        return ChainSelfTestResult(
            name: "DOGE Address Rejects Invalid",
            passed: passed,
            message: passed ? "Invalid address rejected." : "Invalid address unexpectedly accepted."
        )
    }

    private static func testAddressValidationRejectsChecksumMutation() -> ChainSelfTestResult {
        let mutatedAddress = "DA7Q2K7f1k3wX6sVzP8fCBxNf31xHn3v7H"
        let passed = !AddressValidation.isValidDogecoinAddress(mutatedAddress)
        return ChainSelfTestResult(
            name: "DOGE Address Rejects Bad Checksum",
            passed: passed,
            message: passed ? "Checksum mutation rejected." : "Checksum mutation unexpectedly accepted."
        )
    }

    private static func testSingleProviderRuntimeConfiguration() -> ChainSelfTestResult {
        let networks = DogecoinBalanceService.endpointCatalogByNetwork()
        let mainnet = networks.first { $0.title == "Dogecoin" }?.endpoints ?? []
        let testnet = networks.first { $0.title == "Dogecoin Testnet" }?.endpoints ?? []
        let passed = mainnet == [ChainBackendRegistry.DogecoinRuntimeEndpoints.blockcypherBaseURL]
            && testnet == [ChainBackendRegistry.DogecoinRuntimeEndpoints.blockcypherTestnetBaseURL]
        return ChainSelfTestResult(
            name: "DOGE Single Provider Runtime",
            passed: passed,
            message: passed ? "Dogecoin uses BlockCypher endpoints per network." : "Dogecoin runtime endpoints are not simplified to the BlockCypher-only model."
        )
    }
}

enum EthereumChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] {
        [
            testAddressValidationAcceptsValidAddress(),
            testAddressValidationRejectsGarbage(),
            testReceiveAddressNormalization(),
            testSeedDerivationProducesValidAddress(),
            testTransferPaginationWindow(),
            testTransferPaginationOutOfRange()
        ]
    }

    private static func testAddressValidationAcceptsValidAddress() -> ChainSelfTestResult {
        let address = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
        let passed = AddressValidation.isValidEthereumAddress(address)
        return ChainSelfTestResult(
            name: "ETH Address Validation",
            passed: passed,
            message: passed ? "Valid Ethereum address accepted." : "Valid Ethereum address rejected."
        )
    }

    private static func testAddressValidationRejectsGarbage() -> ChainSelfTestResult {
        let passed = !AddressValidation.isValidEthereumAddress("0x_not_valid")
        return ChainSelfTestResult(
            name: "ETH Address Rejects Invalid",
            passed: passed,
            message: passed ? "Invalid Ethereum address rejected." : "Invalid Ethereum address unexpectedly accepted."
        )
    }

    private static func testReceiveAddressNormalization() -> ChainSelfTestResult {
        let mixedCaseAddress = "0x52908400098527886E0F7030069857D2E4169EE7"
        let passed = (try? EthereumWalletEngine.receiveAddress(for: mixedCaseAddress)) == mixedCaseAddress.lowercased()
        return ChainSelfTestResult(
            name: "ETH Receive Address Normalization",
            passed: passed,
            message: passed ? "Receive address normalized successfully." : "Receive address normalization failed."
        )
    }

    private static func testSeedDerivationProducesValidAddress() -> ChainSelfTestResult {
        let mnemonic = "test test test test test test test test test test test junk"
        guard let derivedAddress = try? EthereumWalletEngine.derivedAddress(for: mnemonic) else {
            return ChainSelfTestResult(
                name: "ETH Seed Derivation",
                passed: false,
                message: "Failed to derive an Ethereum address from a valid mnemonic."
            )
        }
        let passed = AddressValidation.isValidEthereumAddress(derivedAddress)
        return ChainSelfTestResult(
            name: "ETH Seed Derivation",
            passed: passed,
            message: passed ? "Mnemonic-derived Ethereum address is valid." : "Derived address format is invalid."
        )
    }

    private static func testTransferPaginationWindow() -> ChainSelfTestResult {
        #if DEBUG
        let snapshots = sampleTransferSnapshots(count: 7)
        let page = EthereumWalletEngine.paginateTransferSnapshotsForTesting(snapshots, page: 2, pageSize: 3)
        let expectedHashes = Array(snapshots[3...5]).map(\.transactionHash)
        let actualHashes = page.map(\.transactionHash)
        let passed = actualHashes == expectedHashes
        return ChainSelfTestResult(
            name: "ETH Transfer Pagination Window",
            passed: passed,
            message: passed ? "Page window slice returned expected transfer range." : "Pagination slice did not match expected range."
        )
        #else
        return ChainSelfTestResult(
            name: "ETH Transfer Pagination Window",
            passed: true,
            message: "Skipped outside DEBUG build."
        )
        #endif
    }

    private static func testTransferPaginationOutOfRange() -> ChainSelfTestResult {
        #if DEBUG
        let snapshots = sampleTransferSnapshots(count: 5)
        let page = EthereumWalletEngine.paginateTransferSnapshotsForTesting(snapshots, page: 4, pageSize: 2)
        let passed = page.isEmpty
        return ChainSelfTestResult(
            name: "ETH Transfer Pagination Out Of Range",
            passed: passed,
            message: passed ? "Out-of-range page returns empty result." : "Out-of-range pagination should return no transfers."
        )
        #else
        return ChainSelfTestResult(
            name: "ETH Transfer Pagination Out Of Range",
            passed: true,
            message: "Skipped outside DEBUG build."
        )
        #endif
    }

    private static func sampleTransferSnapshots(count: Int) -> [EthereumTokenTransferSnapshot] {
        (0..<count).map { index in
            EthereumTokenTransferSnapshot(
                contractAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
                tokenName: "Tether USD",
                symbol: "USDT",
                decimals: 6,
                fromAddress: "0x1111111111111111111111111111111111111111",
                toAddress: "0x2222222222222222222222222222222222222222",
                amount: Decimal(index + 1),
                transactionHash: "0xhash\(index)",
                blockNumber: 1000 - index,
                logIndex: index,
                timestamp: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + index))
            )
        }
    }
}

@MainActor
private enum GenericChainSelfTestHelpers {
    static let mnemonic = "test test test test test test test test test test test junk"

    static func addressAccepts(chainLabel: String, address: String, validator: (String) -> Bool) -> ChainSelfTestResult {
        let passed = validator(address)
        return ChainSelfTestResult(
            name: "\(chainLabel) Address Validation",
            passed: passed,
            message: passed ? "Valid \(chainLabel) address accepted." : "Valid \(chainLabel) address rejected."
        )
    }

    static func addressRejects(chainLabel: String, invalidAddress: String, validator: (String) -> Bool) -> ChainSelfTestResult {
        let passed = !validator(invalidAddress)
        return ChainSelfTestResult(
            name: "\(chainLabel) Address Rejects Invalid",
            passed: passed,
            message: passed ? "Invalid \(chainLabel) address rejected." : "Invalid \(chainLabel) address unexpectedly accepted."
        )
    }

    static func derivationProducesValidAddress(
        chainLabel: String,
        derive: () throws -> String,
        validator: (String) -> Bool
    ) -> ChainSelfTestResult {
        guard let derivedAddress = try? derive() else {
            return ChainSelfTestResult(
                name: "\(chainLabel) Seed Derivation",
                passed: false,
                message: "Failed to derive a \(chainLabel) address from a valid mnemonic."
            )
        }
        let passed = validator(derivedAddress)
        return ChainSelfTestResult(
            name: "\(chainLabel) Seed Derivation",
            passed: passed,
            message: passed ? "Mnemonic-derived \(chainLabel) address is valid." : "Derived \(chainLabel) address format is invalid."
        )
    }
}

@MainActor
enum BitcoinSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] {
        [
            GenericChainSelfTestHelpers.addressAccepts(
                chainLabel: "Bitcoin",
                address: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080",
                validator: { AddressValidation.isValidBitcoinAddress($0, networkMode: .mainnet) }
            ),
            GenericChainSelfTestHelpers.addressRejects(
                chainLabel: "Bitcoin",
                invalidAddress: "bc1_not_valid",
                validator: { AddressValidation.isValidBitcoinAddress($0, networkMode: .mainnet) }
            ),
            GenericChainSelfTestHelpers.derivationProducesValidAddress(
                chainLabel: "Bitcoin",
                derive: { try WalletCoreDerivation.deriveMaterial(seedPhrase: GenericChainSelfTestHelpers.mnemonic, coin: .bitcoin).address },
                validator: { AddressValidation.isValidBitcoinAddress($0, networkMode: .mainnet) }
            )
        ]
    }
}

@MainActor
enum BitcoinCashSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] {
        [
            GenericChainSelfTestHelpers.addressAccepts(
                chainLabel: "Bitcoin Cash",
                address: "bitcoincash:qq07d3s9k4u8x7n5e9qj6m4eht0n5k7n3w6d5m9c8w",
                validator: AddressValidation.isValidBitcoinCashAddress
            ),
            GenericChainSelfTestHelpers.addressRejects(
                chainLabel: "Bitcoin Cash",
                invalidAddress: "bitcoincash:not_valid",
                validator: AddressValidation.isValidBitcoinCashAddress
            ),
            GenericChainSelfTestHelpers.derivationProducesValidAddress(
                chainLabel: "Bitcoin Cash",
                derive: { try BitcoinCashWalletEngine.derivedAddress(for: GenericChainSelfTestHelpers.mnemonic) },
                validator: AddressValidation.isValidBitcoinCashAddress
            )
        ]
    }
}

@MainActor
enum LitecoinSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] {
        [
            GenericChainSelfTestHelpers.addressAccepts(
                chainLabel: "Litecoin",
                address: "ltc1qg82u8my75w4q8k4s4w9q3k6v7d9s8g0j4qg3s6",
                validator: AddressValidation.isValidLitecoinAddress
            ),
            GenericChainSelfTestHelpers.addressRejects(
                chainLabel: "Litecoin",
                invalidAddress: "ltc_not_valid",
                validator: AddressValidation.isValidLitecoinAddress
            ),
            GenericChainSelfTestHelpers.derivationProducesValidAddress(
                chainLabel: "Litecoin",
                derive: { try LitecoinWalletEngine.derivedAddress(for: GenericChainSelfTestHelpers.mnemonic) },
                validator: AddressValidation.isValidLitecoinAddress
            )
        ]
    }
}

@MainActor
enum BitcoinSVSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] {
        [
            GenericChainSelfTestHelpers.addressAccepts(
                chainLabel: "Bitcoin SV",
                address: "1MirQ9bwyQcGVJPwKUgapu5ouK2E2Ey4gX",
                validator: AddressValidation.isValidBitcoinSVAddress
            ),
            GenericChainSelfTestHelpers.addressRejects(
                chainLabel: "Bitcoin SV",
                invalidAddress: "bsv_not_valid",
                validator: AddressValidation.isValidBitcoinSVAddress
            ),
            GenericChainSelfTestHelpers.derivationProducesValidAddress(
                chainLabel: "Bitcoin SV",
                derive: { try BitcoinSVWalletEngine.derivedAddress(for: GenericChainSelfTestHelpers.mnemonic) },
                validator: AddressValidation.isValidBitcoinSVAddress
            )
        ]
    }
}

@MainActor
enum CardanoSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] {
        [
            GenericChainSelfTestHelpers.addressAccepts(
                chainLabel: "Cardano",
                address: "addr1q9d6m0vxj4j6f0r2k6zk6n6w6r0v9x9k5n0d5u7r3q8v9w7c5m0h2g8t7u6k5a4s3d2f1g0h9j8k7l6m5n4p3q2r1s",
                validator: AddressValidation.isValidCardanoAddress
            ),
            GenericChainSelfTestHelpers.addressRejects(
                chainLabel: "Cardano",
                invalidAddress: "addr_not_valid",
                validator: AddressValidation.isValidCardanoAddress
            ),
            GenericChainSelfTestHelpers.derivationProducesValidAddress(
                chainLabel: "Cardano",
                derive: { try CardanoWalletEngine.derivedAddress(for: GenericChainSelfTestHelpers.mnemonic) },
                validator: AddressValidation.isValidCardanoAddress
            )
        ]
    }
}

@MainActor
enum SolanaChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] {
        [
            GenericChainSelfTestHelpers.addressAccepts(
                chainLabel: "Solana",
                address: "Vote111111111111111111111111111111111111111",
                validator: AddressValidation.isValidSolanaAddress
            ),
            GenericChainSelfTestHelpers.addressRejects(
                chainLabel: "Solana",
                invalidAddress: "sol_not_valid",
                validator: AddressValidation.isValidSolanaAddress
            ),
            GenericChainSelfTestHelpers.derivationProducesValidAddress(
                chainLabel: "Solana",
                derive: { try SolanaWalletEngine.derivedAddress(for: GenericChainSelfTestHelpers.mnemonic) },
                validator: AddressValidation.isValidSolanaAddress
            )
        ]
    }
}

@MainActor
enum StellarSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] {
        [
            GenericChainSelfTestHelpers.addressAccepts(
                chainLabel: "Stellar",
                address: "GBRPYHIL2C4F7Q4W6H6OL5K2C4BFRJHC7YQ7AZZLQ6G4Z7D4VJ4M6N4K",
                validator: AddressValidation.isValidStellarAddress
            ),
            GenericChainSelfTestHelpers.addressRejects(
                chainLabel: "Stellar",
                invalidAddress: "stellar_not_valid",
                validator: AddressValidation.isValidStellarAddress
            ),
            GenericChainSelfTestHelpers.derivationProducesValidAddress(
                chainLabel: "Stellar",
                derive: { try StellarWalletEngine.derivedAddress(for: GenericChainSelfTestHelpers.mnemonic) },
                validator: AddressValidation.isValidStellarAddress
            )
        ]
    }
}

@MainActor
enum XRPChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] {
        [
            GenericChainSelfTestHelpers.addressAccepts(
                chainLabel: "XRP",
                address: "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh",
                validator: AddressValidation.isValidXRPAddress
            ),
            GenericChainSelfTestHelpers.addressRejects(
                chainLabel: "XRP",
                invalidAddress: "xrp_not_valid",
                validator: AddressValidation.isValidXRPAddress
            ),
            GenericChainSelfTestHelpers.derivationProducesValidAddress(
                chainLabel: "XRP",
                derive: { try XRPWalletEngine.derivedAddress(for: GenericChainSelfTestHelpers.mnemonic) },
                validator: AddressValidation.isValidXRPAddress
            )
        ]
    }
}

@MainActor
enum TronChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] {
        [
            GenericChainSelfTestHelpers.addressAccepts(
                chainLabel: "Tron",
                address: "TNPeeaaFB7K9cmo4uQpcU32zGK8G1NYqeL",
                validator: AddressValidation.isValidTronAddress
            ),
            GenericChainSelfTestHelpers.addressRejects(
                chainLabel: "Tron",
                invalidAddress: "tron_not_valid",
                validator: AddressValidation.isValidTronAddress
            ),
            GenericChainSelfTestHelpers.derivationProducesValidAddress(
                chainLabel: "Tron",
                derive: { try WalletCoreDerivation.deriveMaterial(seedPhrase: GenericChainSelfTestHelpers.mnemonic, coin: .tron).address },
                validator: AddressValidation.isValidTronAddress
            )
        ]
    }
}

@MainActor
enum SuiChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] {
        [
            GenericChainSelfTestHelpers.addressAccepts(
                chainLabel: "Sui",
                address: "0x5f1e6bc4b4f4d7e4d4b5e7a6c3b2a1f0e9d8c7b6a5f4e3d2c1b0a9876543210f",
                validator: AddressValidation.isValidSuiAddress
            ),
            GenericChainSelfTestHelpers.addressRejects(
                chainLabel: "Sui",
                invalidAddress: "0xnotvalid",
                validator: AddressValidation.isValidSuiAddress
            ),
            GenericChainSelfTestHelpers.derivationProducesValidAddress(
                chainLabel: "Sui",
                derive: { try SuiWalletEngine.derivedAddress(for: GenericChainSelfTestHelpers.mnemonic) },
                validator: AddressValidation.isValidSuiAddress
            )
        ]
    }
}

@MainActor
enum AptosChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] {
        [
            GenericChainSelfTestHelpers.addressAccepts(
                chainLabel: "Aptos",
                address: "0x1",
                validator: AddressValidation.isValidAptosAddress
            ),
            GenericChainSelfTestHelpers.addressRejects(
                chainLabel: "Aptos",
                invalidAddress: "aptos_not_valid",
                validator: AddressValidation.isValidAptosAddress
            ),
            GenericChainSelfTestHelpers.derivationProducesValidAddress(
                chainLabel: "Aptos",
                derive: { try AptosWalletEngine.derivedAddress(for: GenericChainSelfTestHelpers.mnemonic) },
                validator: AddressValidation.isValidAptosAddress
            )
        ]
    }
}

@MainActor
enum TONChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] {
        [
            GenericChainSelfTestHelpers.addressAccepts(
                chainLabel: "TON",
                address: "UQBm--PFwDv1yCeS-QTJ-L8oiUpqo9IT1BwgVptlSq3ts4DV",
                validator: AddressValidation.isValidTONAddress
            ),
            GenericChainSelfTestHelpers.addressRejects(
                chainLabel: "TON",
                invalidAddress: "ton_not_valid",
                validator: AddressValidation.isValidTONAddress
            ),
            GenericChainSelfTestHelpers.derivationProducesValidAddress(
                chainLabel: "TON",
                derive: { try TONWalletEngine.derivedAddress(for: GenericChainSelfTestHelpers.mnemonic) },
                validator: AddressValidation.isValidTONAddress
            )
        ]
    }
}

@MainActor
enum ICPChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] {
        [
            GenericChainSelfTestHelpers.addressAccepts(
                chainLabel: "Internet Computer",
                address: "be2us-64aaa-aaaaa-qaabq-cai",
                validator: AddressValidation.isValidICPAddress
            ),
            GenericChainSelfTestHelpers.addressRejects(
                chainLabel: "Internet Computer",
                invalidAddress: "icp_not_valid",
                validator: AddressValidation.isValidICPAddress
            ),
            GenericChainSelfTestHelpers.derivationProducesValidAddress(
                chainLabel: "Internet Computer",
                derive: { try ICPWalletEngine.derivedAddress(for: GenericChainSelfTestHelpers.mnemonic) },
                validator: AddressValidation.isValidICPAddress
            )
        ]
    }
}

@MainActor
enum NearChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] {
        [
            GenericChainSelfTestHelpers.addressAccepts(
                chainLabel: "NEAR",
                address: "example.near",
                validator: AddressValidation.isValidNearAddress
            ),
            GenericChainSelfTestHelpers.addressRejects(
                chainLabel: "NEAR",
                invalidAddress: "-not-valid.near",
                validator: AddressValidation.isValidNearAddress
            ),
            GenericChainSelfTestHelpers.derivationProducesValidAddress(
                chainLabel: "NEAR",
                derive: { try NearWalletEngine.derivedAddress(for: GenericChainSelfTestHelpers.mnemonic) },
                validator: AddressValidation.isValidNearAddress
            )
        ]
    }
}

@MainActor
enum PolkadotChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] {
        [
            GenericChainSelfTestHelpers.addressAccepts(
                chainLabel: "Polkadot",
                address: "15oF4u3gP5xY8J8cH7W5WqJ9wS6XtK9vYw7R1oL2nQm1QdKp",
                validator: AddressValidation.isValidPolkadotAddress
            ),
            GenericChainSelfTestHelpers.addressRejects(
                chainLabel: "Polkadot",
                invalidAddress: "dot_not_valid",
                validator: AddressValidation.isValidPolkadotAddress
            ),
            GenericChainSelfTestHelpers.derivationProducesValidAddress(
                chainLabel: "Polkadot",
                derive: { try PolkadotWalletEngine.derivedAddress(for: GenericChainSelfTestHelpers.mnemonic) },
                validator: AddressValidation.isValidPolkadotAddress
            )
        ]
    }
}

@MainActor
enum MoneroChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] {
        [
            GenericChainSelfTestHelpers.addressAccepts(
                chainLabel: "Monero",
                address: "47zQ5w3QJ9P4hJ2sD7v8QnE9mQfQv7s3y6Fq1v6F5g4Yv7dL1m4rV4bW2tK4w9W8nS2b8S8i3Q2vX5M8Q1n7w6Jp1q2x3Q",
                validator: AddressValidation.isValidMoneroAddress
            ),
            GenericChainSelfTestHelpers.addressRejects(
                chainLabel: "Monero",
                invalidAddress: "xmr_not_valid",
                validator: AddressValidation.isValidMoneroAddress
            )
        ]
    }
}

@MainActor
enum BNBChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] {
        [
            GenericChainSelfTestHelpers.addressAccepts(
                chainLabel: "BNB Chain",
                address: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
                validator: AddressValidation.isValidEthereumAddress
            ),
            GenericChainSelfTestHelpers.addressRejects(
                chainLabel: "BNB Chain",
                invalidAddress: "0x_not_valid",
                validator: AddressValidation.isValidEthereumAddress
            ),
            GenericChainSelfTestHelpers.derivationProducesValidAddress(
                chainLabel: "BNB Chain",
                derive: { try EthereumWalletEngine.derivedAddress(for: GenericChainSelfTestHelpers.mnemonic, chain: .bnb) },
                validator: AddressValidation.isValidEthereumAddress
            )
        ]
    }
}

@MainActor
enum AvalancheChainSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] {
        [
            GenericChainSelfTestHelpers.addressAccepts(
                chainLabel: "Avalanche",
                address: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
                validator: AddressValidation.isValidEthereumAddress
            ),
            GenericChainSelfTestHelpers.addressRejects(
                chainLabel: "Avalanche",
                invalidAddress: "0x_not_valid",
                validator: AddressValidation.isValidEthereumAddress
            ),
            GenericChainSelfTestHelpers.derivationProducesValidAddress(
                chainLabel: "Avalanche",
                derive: { try EthereumWalletEngine.derivedAddress(for: GenericChainSelfTestHelpers.mnemonic, chain: .avalanche) },
                validator: AddressValidation.isValidEthereumAddress
            )
        ]
    }
}

@MainActor
enum EthereumClassicSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] {
        [
            GenericChainSelfTestHelpers.addressAccepts(
                chainLabel: "Ethereum Classic",
                address: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
                validator: AddressValidation.isValidEthereumAddress
            ),
            GenericChainSelfTestHelpers.addressRejects(
                chainLabel: "Ethereum Classic",
                invalidAddress: "0x_not_valid",
                validator: AddressValidation.isValidEthereumAddress
            ),
            GenericChainSelfTestHelpers.derivationProducesValidAddress(
                chainLabel: "Ethereum Classic",
                derive: { try EthereumWalletEngine.derivedAddress(for: GenericChainSelfTestHelpers.mnemonic, chain: .ethereumClassic) },
                validator: AddressValidation.isValidEthereumAddress
            )
        ]
    }
}

@MainActor
enum HyperliquidSelfTestSuite {
    static func runAll() -> [ChainSelfTestResult] {
        [
            GenericChainSelfTestHelpers.addressAccepts(
                chainLabel: "Hyperliquid",
                address: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
                validator: AddressValidation.isValidEthereumAddress
            ),
            GenericChainSelfTestHelpers.addressRejects(
                chainLabel: "Hyperliquid",
                invalidAddress: "0x_not_valid",
                validator: AddressValidation.isValidEthereumAddress
            ),
            GenericChainSelfTestHelpers.derivationProducesValidAddress(
                chainLabel: "Hyperliquid",
                derive: { try EthereumWalletEngine.derivedAddress(for: GenericChainSelfTestHelpers.mnemonic, chain: .hyperliquid) },
                validator: AddressValidation.isValidEthereumAddress
            )
        ]
    }
}

@MainActor
enum AllChainsSelfTestSuite {
    static func runAll() -> [String: [ChainSelfTestResult]] {
        [
            "Bitcoin": BitcoinSelfTestSuite.runAll(),
            "Bitcoin Cash": BitcoinCashSelfTestSuite.runAll(),
            "Litecoin": LitecoinSelfTestSuite.runAll(),
            "Cardano": CardanoSelfTestSuite.runAll(),
            "Solana": SolanaChainSelfTestSuite.runAll(),
            "Stellar": StellarSelfTestSuite.runAll(),
            "XRP": XRPChainSelfTestSuite.runAll(),
            "Tron": TronChainSelfTestSuite.runAll(),
            "Sui": SuiChainSelfTestSuite.runAll(),
            "Aptos": AptosChainSelfTestSuite.runAll(),
            "TON": TONChainSelfTestSuite.runAll(),
            "Internet Computer": ICPChainSelfTestSuite.runAll(),
            "NEAR": NearChainSelfTestSuite.runAll(),
            "Polkadot": PolkadotChainSelfTestSuite.runAll(),
            "Monero": MoneroChainSelfTestSuite.runAll(),
            "BNB Chain": BNBChainSelfTestSuite.runAll(),
            "Avalanche": AvalancheChainSelfTestSuite.runAll(),
            "Ethereum Classic": EthereumClassicSelfTestSuite.runAll(),
            "Hyperliquid": HyperliquidSelfTestSuite.runAll()
        ]
    }
}
