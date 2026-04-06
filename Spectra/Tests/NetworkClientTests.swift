import Foundation
import XCTest
@testable import Spectra

@MainActor
class SpectraNetworkTestCase: XCTestCase {
    var testNetworkClient: TestSpectraNetworkClient!

    func resetTestState() async throws {}

    override func setUp() async throws {
        try await super.setUp()
        testNetworkClient = TestSpectraNetworkClient()
        await SpectraNetworkRouter.shared.install(client: testNetworkClient)
        try await resetTestState()
    }

    override func tearDown() async throws {
        await SpectraNetworkRouter.shared.resetToDefault()
        testNetworkClient = nil
        try await super.tearDown()
    }

    func assertThrowsURLErrorCode(
        _ expectedCode: URLError.Code,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected URLError(\(expectedCode.rawValue)) to be thrown", file: file, line: line)
        } catch {
            guard let urlError = error as? URLError else {
                XCTFail("Expected URLError, got \(type(of: error))", file: file, line: line)
                return
            }
            XCTAssertEqual(urlError.code, expectedCode, file: file, line: line)
        }
    }
}

@MainActor
private func makeSingleChainDraft(select: (WalletImportDraft) -> Void) -> WalletImportDraft {
    let draft = WalletImportDraft()
    select(draft)
    return draft
}

private func chainWikiEntry(id: String) throws -> ChainWikiEntry {
    try XCTUnwrap(ChainRegistryEntry.entry(id: id).map {
        ChainWikiEntry(
            id: $0.id,
            name: $0.name,
            symbol: $0.symbol,
            tags: [],
            family: $0.family,
            consensus: $0.consensus,
            stateModel: $0.stateModel,
            primaryUse: $0.primaryUse,
            slip44CoinType: $0.slip44CoinType,
            derivationPath: $0.derivationPath,
            alternateDerivationPath: $0.alternateDerivationPath,
            totalCirculationModel: $0.totalCirculationModel,
            notableDetails: $0.notableDetails
        )
    })
}

@MainActor
final class TestSpectraNetworkClientTests: SpectraNetworkTestCase {
    @MainActor
    func testConsumesQueuedResponsesDeterministically() async throws {
        let urlString = "https://example.test/ping"
        await testNetworkClient.enqueueResponse(url: urlString, statusCode: 200, body: Data("ok".utf8))

        let request = URLRequest(url: URL(string: urlString)!)
        let (data, response) = try await SpectraNetworkRouter.shared.data(for: request, profile: .chainRead)

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(data: data, encoding: .utf8), "ok")

        await assertThrowsURLErrorCode(.resourceUnavailable) {
            _ = try await SpectraNetworkRouter.shared.data(for: request, profile: .chainRead)
        }
    }

    @MainActor
    func testQueuesAreIsolatedByHTTPMethod() async throws {
        let urlString = "https://example.test/resource"
        await testNetworkClient.enqueueResponse(method: "GET", url: urlString, statusCode: 200, body: Data("get".utf8))
        await testNetworkClient.enqueueResponse(method: "POST", url: urlString, statusCode: 201, body: Data("post".utf8))

        var getRequest = URLRequest(url: URL(string: urlString)!)
        getRequest.httpMethod = "GET"
        var postRequest = URLRequest(url: URL(string: urlString)!)
        postRequest.httpMethod = "POST"

        let (getData, getResponse) = try await SpectraNetworkRouter.shared.data(for: getRequest, profile: .chainRead)
        let (postData, postResponse) = try await SpectraNetworkRouter.shared.data(for: postRequest, profile: .chainRead)

        XCTAssertEqual((getResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(data: getData, encoding: .utf8), "get")

        XCTAssertEqual((postResponse as? HTTPURLResponse)?.statusCode, 201)
        XCTAssertEqual(String(data: postData, encoding: .utf8), "post")
    }
}

@MainActor
final class EthereumClassicSupportTests: XCTestCase {
    func testEthereumClassicEVMContextUsesDedicatedDefaults() {
        XCTAssertEqual(EVMChainContext.ethereumClassic.displayName, "Ethereum Classic")
        XCTAssertEqual(EVMChainContext.ethereumClassic.expectedChainID, 61)
        XCTAssertEqual(EVMChainContext.ethereumClassic.defaultDerivationPath, "m/44'/61'/0'/0/0")
        XCTAssertEqual(EVMChainContext.ethereumClassic.derivationPath(account: 2), "m/44'/61'/2'/0/0")
        XCTAssertTrue(EVMChainContext.ethereumClassic.defaultRPCEndpoints.contains("https://etc.rivet.link"))
    }

    func testEthereumClassicImportSelectionProducesNativeETCCoin() throws {
        let draft = makeSingleChainDraft { $0.wantsEthereumClassic = true }

        XCTAssertEqual(draft.selectedChainNames, ["Ethereum Classic"])

        let etcCoin = try XCTUnwrap(
            draft.selectedCoins.first { $0.chainName == "Ethereum Classic" && $0.symbol == "ETC" }
        )
        XCTAssertEqual(etcCoin.name, "Ethereum Classic")
        XCTAssertEqual(etcCoin.coinGeckoID, "ethereum-classic")
        XCTAssertEqual(etcCoin.marketDataID, "1321")
        XCTAssertNil(etcCoin.contractAddress)
    }

    func testEthereumClassicChainWikiEntryIsPresent() throws {
        let chain = try chainWikiEntry(id: "ethereum-classic")
        XCTAssertEqual(chain.name, "Ethereum Classic")
        XCTAssertEqual(chain.symbol, "ETC")
        XCTAssertEqual(chain.derivationPath, "m/44'/61'/0'/0/0")
    }
}

@MainActor
final class AvalancheSupportTests: XCTestCase {
    func testAvalancheEVMContextUsesDedicatedDefaults() {
        XCTAssertEqual(EVMChainContext.avalanche.displayName, "Avalanche")
        XCTAssertEqual(EVMChainContext.avalanche.expectedChainID, 43114)
        XCTAssertEqual(EVMChainContext.avalanche.defaultDerivationPath, "m/44'/60'/0'/0/0")
        XCTAssertEqual(EVMChainContext.avalanche.derivationPath(account: 2), "m/44'/60'/2'/0/0")
        XCTAssertTrue(EVMChainContext.avalanche.defaultRPCEndpoints.contains("https://api.avax.network/ext/bc/C/rpc"))
    }

    func testAvalancheImportSelectionProducesNativeAVAXCoin() throws {
        let draft = makeSingleChainDraft { $0.wantsAvalanche = true }

        XCTAssertEqual(draft.selectedChainNames, ["Avalanche"])

        let avaxCoin = try XCTUnwrap(
            draft.selectedCoins.first { $0.chainName == "Avalanche" && $0.symbol == "AVAX" }
        )
        XCTAssertEqual(avaxCoin.name, "Avalanche")
        XCTAssertEqual(avaxCoin.coinGeckoID, "avalanche-2")
        XCTAssertEqual(avaxCoin.marketDataID, "5805")
        XCTAssertNil(avaxCoin.contractAddress)
    }

    func testAvalancheChainWikiEntryIsPresent() throws {
        let chain = try chainWikiEntry(id: "avalanche")
        XCTAssertEqual(chain.name, "Avalanche")
        XCTAssertEqual(chain.symbol, "AVAX")
        XCTAssertEqual(chain.derivationPath, "m/44'/60'/0'/0/0")
    }
}

@MainActor
final class HyperliquidSupportTests: XCTestCase {
    func testHyperliquidEVMContextUsesDedicatedDefaults() {
        XCTAssertEqual(EVMChainContext.hyperliquid.displayName, "Hyperliquid")
        XCTAssertEqual(EVMChainContext.hyperliquid.expectedChainID, 999)
        XCTAssertEqual(EVMChainContext.hyperliquid.defaultDerivationPath, "m/44'/60'/0'/0/0")
        XCTAssertEqual(EVMChainContext.hyperliquid.derivationPath(account: 2), "m/44'/60'/2'/0/0")
        XCTAssertTrue(EVMChainContext.hyperliquid.defaultRPCEndpoints.contains("https://rpc.hyperliquid.xyz/evm"))
    }

    func testHyperliquidImportSelectionProducesNativeHYPECoin() throws {
        let draft = makeSingleChainDraft { $0.wantsHyperliquid = true }

        XCTAssertEqual(draft.selectedChainNames, ["Hyperliquid"])

        let hypeCoin = try XCTUnwrap(
            draft.selectedCoins.first { $0.chainName == "Hyperliquid" && $0.symbol == "HYPE" }
        )
        XCTAssertEqual(hypeCoin.name, "Hyperliquid")
        XCTAssertEqual(hypeCoin.coinGeckoID, "hyperliquid")
        XCTAssertEqual(hypeCoin.marketDataID, "0")
        XCTAssertNil(hypeCoin.contractAddress)
    }

    func testHyperliquidChainWikiEntryIsPresent() throws {
        let chain = try chainWikiEntry(id: "hyperliquid")
        XCTAssertEqual(chain.name, "Hyperliquid")
        XCTAssertEqual(chain.symbol, "HYPE")
        XCTAssertEqual(chain.derivationPath, "m/44'/60'/0'/0/0")
    }
}

@MainActor
final class AptosSupportTests: XCTestCase {
    func testAptosImportSelectionProducesNativeAPTCoin() throws {
        let draft = makeSingleChainDraft { $0.wantsAptos = true }

        XCTAssertEqual(draft.selectedChainNames, ["Aptos"])

        let aptCoin = try XCTUnwrap(
            draft.selectedCoins.first { $0.chainName == "Aptos" && $0.symbol == "APT" }
        )
        XCTAssertEqual(aptCoin.name, "Aptos")
        XCTAssertEqual(aptCoin.coinGeckoID, "aptos")
        XCTAssertNil(aptCoin.contractAddress)
    }

    func testAptosChainWikiEntryIsPresent() throws {
        let chain = try chainWikiEntry(id: "aptos")
        XCTAssertEqual(chain.name, "Aptos")
        XCTAssertEqual(chain.symbol, "APT")
        XCTAssertEqual(chain.derivationPath, "m/44'/637'/0'/0'/0'")
    }
}

@MainActor
final class NearHistoryParsingTests: XCTestCase {
    func testParsesNearBlocksHistoryPackageWithPredecessorAndReceiptBlock() throws {
        let owner = "alice.near"
        let payload: [String: Any] = [
            "txns": [
                [
                    "transaction_hash": "hash-send-1",
                    "predecessor_account_id": owner,
                    "receiver_account_id": "merchant.near",
                    "receipt_block": [
                        "block_timestamp": "1726000000000000000"
                    ],
                    "actions_agg": [
                        "deposit": "1500000000000000000000000"
                    ]
                ],
                [
                    "transaction_hash": "hash-receive-1",
                    "predecessor_account_id": "payer.near",
                    "receiver_account_id": owner,
                    "receipt_block": [
                        "block_timestamp": "1726000100000000000"
                    ],
                    "actions": [
                        [
                            "args": [
                                "deposit": "2500000000000000000000000"
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        let snapshots = try NearBalanceService.parseHistoryResponse(data, ownerAddress: owner)

        XCTAssertEqual(snapshots.count, 2)

        let send = try XCTUnwrap(snapshots.first(where: { $0.transactionHash == "hash-send-1" }))
        XCTAssertEqual(send.kind, .send)
        XCTAssertEqual(send.counterpartyAddress, "merchant.near")
        XCTAssertEqual(send.amount, 1.5, accuracy: 0.0000001)

        let receive = try XCTUnwrap(snapshots.first(where: { $0.transactionHash == "hash-receive-1" }))
        XCTAssertEqual(receive.kind, .receive)
        XCTAssertEqual(receive.counterpartyAddress, "payer.near")
        XCTAssertEqual(receive.amount, 2.5, accuracy: 0.0000001)
    }
}

@MainActor
final class StellarSupportTests: XCTestCase {
    func testStellarImportSelectionProducesNativeXLMCoin() throws {
        let draft = makeSingleChainDraft { $0.wantsStellar = true }

        XCTAssertEqual(draft.selectedChainNames, ["Stellar"])

        let xlmCoin = try XCTUnwrap(
            draft.selectedCoins.first { $0.chainName == "Stellar" && $0.symbol == "XLM" }
        )
        XCTAssertEqual(xlmCoin.name, "Stellar Lumens")
        XCTAssertEqual(xlmCoin.coinGeckoID, "stellar")
        XCTAssertNil(xlmCoin.contractAddress)
    }

    func testStellarChainWikiEntryIsPresent() throws {
        let chain = try chainWikiEntry(id: "stellar")
        XCTAssertEqual(chain.name, "Stellar")
        XCTAssertEqual(chain.symbol, "XLM")
        XCTAssertEqual(chain.derivationPath, "m/44'/148'/0'")
    }
}

@MainActor
final class ICPSupportTests: XCTestCase {
    func testICPImportSelectionProducesNativeICPCoin() throws {
        let draft = makeSingleChainDraft { $0.wantsICP = true }

        XCTAssertEqual(draft.selectedChainNames, ["Internet Computer"])

        let icpCoin = try XCTUnwrap(
            draft.selectedCoins.first { $0.chainName == "Internet Computer" && $0.symbol == "ICP" }
        )
        XCTAssertEqual(icpCoin.name, "Internet Computer")
        XCTAssertEqual(icpCoin.coinGeckoID, "internet-computer")
        XCTAssertNil(icpCoin.contractAddress)
    }

    func testICPChainWikiEntryIsPresent() throws {
        let chain = try chainWikiEntry(id: "internet-computer")
        XCTAssertEqual(chain.name, "Internet Computer")
        XCTAssertEqual(chain.symbol, "ICP")
        XCTAssertEqual(chain.derivationPath, "m/44'/223'/0'/0/0")
    }
}

@MainActor
final class TronDerivationSupportTests: XCTestCase {
    func testTronDerivationPresetsIncludeLegacyVariants() throws {
        let presets = SeedDerivationChain.tron.presetOptions

        XCTAssertEqual(presets.first?.path, "m/44'/195'/0'/0/0")
        XCTAssertTrue(presets.contains { $0.title == "Simple BIP44" && $0.path == "m/44'/195'/0'" })
        XCTAssertTrue(presets.contains { $0.title == "Legacy" && $0.path == "m/44'/60'/0'/0/0" })
    }

    func testTronLegacyEthereumStylePathResolvesAsLegacyFlavor() {
        let resolution = SeedDerivationChain.tron.resolve(path: "m/44'/60'/0'/0/0")

        XCTAssertEqual(resolution.normalizedPath, "m/44'/60'/0'/0/0")
        XCTAssertEqual(resolution.accountIndex, 0)
        XCTAssertEqual(resolution.flavor, .legacy)
    }

    func testTronSimpleBIP44PathResolvesAsLegacyFlavor() {
        let resolution = SeedDerivationChain.tron.resolve(path: "m/44'/195'/0'")

        XCTAssertEqual(resolution.normalizedPath, "m/44'/195'/0'")
        XCTAssertEqual(resolution.accountIndex, 0)
        XCTAssertEqual(resolution.flavor, .legacy)
    }
}

@MainActor
final class BitcoinCashDerivationSupportTests: XCTestCase {
    func testBitcoinCashDerivationPresetsIncludeElectrumLegacyPath() {
        let presets = SeedDerivationChain.bitcoinCash.presetOptions

        XCTAssertTrue(presets.contains { $0.title == "Electrum Legacy" && $0.path == "m/0" })
    }

    func testBitcoinCashElectrumLegacyPathResolvesAsElectrumLegacyFlavor() {
        let resolution = SeedDerivationChain.bitcoinCash.resolve(path: "m/0")

        XCTAssertEqual(resolution.normalizedPath, "m/0")
        XCTAssertEqual(resolution.accountIndex, 0)
        XCTAssertEqual(resolution.flavor, .electrumLegacy)
    }
}

@MainActor
final class XRPDerivationSupportTests: XCTestCase {
    func testXRPPresetsIncludeSimpleBIP44Path() {
        let presets = SeedDerivationChain.xrp.presetOptions

        XCTAssertTrue(presets.contains { $0.title == "Simple BIP44" && $0.path == "m/44'/144'/0'" })
    }

    func testXRPSimpleBIP44PathResolvesAsLegacyFlavor() {
        let resolution = SeedDerivationChain.xrp.resolve(path: "m/44'/144'/0'")

        XCTAssertEqual(resolution.normalizedPath, "m/44'/144'/0'")
        XCTAssertEqual(resolution.accountIndex, 0)
        XCTAssertEqual(resolution.flavor, .legacy)
    }
}

@MainActor
final class WalletDerivationEngineTests: XCTestCase {
    private let mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"

    func testBitcoinTestnet4ReturnsOnlyRequestedOutputs() throws {
        let result = try WalletDerivationEngine.derive(
            seedPhrase: mnemonic,
            request: WalletDerivationRequest(
                chain: .bitcoin,
                network: .testnet4,
                derivationPath: "m/84'/1'/0'/0/0",
                curve: .secp256k1,
                requestedOutputs: [.address, .publicKey]
            )
        )

        XCTAssertNotNil(result.address)
        XCTAssertTrue(result.address?.hasPrefix("tb1") == true)
        XCTAssertNotNil(result.publicKeyHex)
        XCTAssertNil(result.privateKeyHex)
    }

    func testSolanaMainnetReturnsRequestedSigningMaterial() throws {
        let result = try WalletDerivationEngine.derive(
            seedPhrase: mnemonic,
            request: WalletDerivationRequest(
                chain: .solana,
                network: .mainnet,
                derivationPath: "m/44'/501'/0'/0'",
                curve: .ed25519,
                requestedOutputs: [.address, .publicKey, .privateKey]
            )
        )

        XCTAssertFalse(result.address?.isEmpty ?? true)
        XCTAssertFalse(result.publicKeyHex?.isEmpty ?? true)
        XCTAssertFalse(result.privateKeyHex?.isEmpty ?? true)
    }

    func testCustomCurveStillDerivesSigningMaterial() throws {
        XCTAssertThrowsError(
            try WalletDerivationEngine.derive(
                seedPhrase: mnemonic,
                request: WalletDerivationRequest(
                    chain: .bitcoin,
                    network: .mainnet,
                    derivationPath: "m/44'/501'/0'/0'",
                    curve: .ed25519,
                    requestedOutputs: [.publicKey, .privateKey]
                )
            )
        )
    }

    func testAddressRequestThrowsForUnsupportedCustomCurve() {
        XCTAssertThrowsError(
            try WalletDerivationEngine.derive(
                seedPhrase: mnemonic,
                request: WalletDerivationRequest(
                    chain: .bitcoin,
                    network: .mainnet,
                    derivationPath: SeedDerivationChain.bitcoin.defaultPath,
                    curve: .ed25519,
                    requestedOutputs: [.address]
                )
            )
        )
    }

    func testJSONAPIRequestSupportsCustomPathAndCurve() throws {
        let request: [String: Any] = [
            "chain": "Solana",
            "network": "mainnet",
            "seedPhrase": mnemonic,
            "derivationPath": "m/44'/501'/9'",
            "curve": "ed25519",
            "passphrase": "",
            "iterationCount": 2048,
            "hmacKeyString": "",
            "requestedOutputs": ["publicKey", "privateKey"],
        ]

        let requestData = try JSONSerialization.data(withJSONObject: request, options: [])
        let responseData = try WalletDerivationEngine.derive(jsonData: requestData)

        struct DerivationJSONResponse: Decodable {
            let address: String?
            let publicKeyHex: String?
            let privateKeyHex: String?
        }
        let response = try JSONDecoder().decode(DerivationJSONResponse.self, from: responseData)

        XCTAssertNil(response.address)
        XCTAssertFalse(response.publicKeyHex?.isEmpty ?? true)
        XCTAssertFalse(response.privateKeyHex?.isEmpty ?? true)
    }

    func testBitcoinAPIPresetsIncludeTestnet4NativeSegWit() {
        let hasPath = WalletDerivationPresetCatalog.pathPresets(for: .bitcoin).contains {
            $0.derivationPath == "m/84'/0'/0'/0/0"
        }
        let hasNetwork = WalletDerivationPresetCatalog.networkPresets(for: .bitcoin).contains {
            $0.network == .testnet4
        }

        XCTAssertTrue(hasPath)
        XCTAssertTrue(hasNetwork)
        XCTAssertEqual(WalletDerivationPresetCatalog.curve(for: .bitcoin), .secp256k1)
    }

    func testSolanaAPIPresetsIncludeLegacyCurveAndPath() {
        let hasPath = WalletDerivationPresetCatalog.pathPresets(for: .solana).contains {
            $0.derivationPath == "m/44'/501'/0'"
        }
        let hasMainnet = WalletDerivationPresetCatalog.networkPresets(for: .solana).contains {
            $0.network == .mainnet
        }

        XCTAssertTrue(hasPath)
        XCTAssertTrue(hasMainnet)
        XCTAssertEqual(WalletDerivationPresetCatalog.curve(for: .solana), .ed25519)
    }
}
