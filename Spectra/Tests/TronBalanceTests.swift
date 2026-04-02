import XCTest
@testable import Spectra

@MainActor
final class TronBalanceServiceTests: SpectraNetworkTestCase {
    private let validAddress = "T" + String(repeating: "A", count: 33)
    private let ownerAddress = TronBalanceService.usdtTronContract
    private let counterpartyAddress = TronBalanceService.usddTronContract

    func testFetchBalancesParsesTronScanNativeAndTokenBalances() async throws {
        let url = "https://apilist.tronscanapi.com/api/accountv2?address=\(validAddress)"
        try await testNetworkClient.enqueueJSONResponse(
            url: url,
            object: [
                "balance": 2_000_000,
                "tokens": [[
                    "tokenAbbr": "USDT",
                    "tokenId": TronBalanceService.usdtTronContract,
                    "tokenDecimal": 6,
                    "balance": "1230000",
                    "tokenType": "trc20"
                ]]
            ]
        )

        let result = try await TronBalanceService.fetchBalances(for: validAddress)
        XCTAssertEqual(result.trxBalance, 2.0, accuracy: 0.0000001)
        XCTAssertEqual(result.tokenBalances.first(where: { $0.symbol == "USDT" })?.balance ?? 0, 1.23, accuracy: 0.0000001)
    }

    func testFetchBalancesParsesTronScanNativeBalanceWhenReturnedAsString() async throws {
        let url = "https://apilist.tronscanapi.com/api/accountv2?address=\(validAddress)"
        try await testNetworkClient.enqueueJSONResponse(
            url: url,
            object: [
                "balance": "2750000",
                "tokens": [[
                    "tokenId": TronBalanceService.usdtTronContract,
                    "balance": "500000"
                ]]
            ]
        )

        let result = try await TronBalanceService.fetchBalances(for: validAddress)
        XCTAssertEqual(result.trxBalance, 2.75, accuracy: 0.0000001)
        XCTAssertEqual(result.tokenBalances.first(where: { $0.symbol == "USDT" })?.balance ?? 0, 0.5, accuracy: 0.0000001)
    }

    func testFetchBalancesFallsBackToTronScanNativeTokenRowForTRXBalance() async throws {
        let url = "https://apilist.tronscanapi.com/api/accountv2?address=\(validAddress)"
        try await testNetworkClient.enqueueJSONResponse(
            url: url,
            object: [
                "balance": 0,
                "tokens": [
                    [
                        "tokenId": "_",
                        "tokenName": "trx",
                        "tokenAbbr": "trx",
                        "tokenDecimal": 6,
                        "tokenType": "trc10",
                        "balance": "155002484"
                    ],
                    [
                        "tokenId": TronBalanceService.usdtTronContract,
                        "balance": "500000"
                    ]
                ]
            ]
        )

        let result = try await TronBalanceService.fetchBalances(for: validAddress)
        XCTAssertEqual(result.trxBalance, 155.002484, accuracy: 0.0000001)
        XCTAssertEqual(result.tokenBalances.first(where: { $0.symbol == "USDT" })?.balance ?? 0, 0.5, accuracy: 0.0000001)
    }

    func testFetchBalancesFallsBackToTronScanStakedResourceBalanceForTRX() async throws {
        let accountURL = "https://apilist.tronscanapi.com/api/accountv2?address=\(validAddress)"
        let resourceURL = "https://apilist.tronscanapi.com/api/account/resourcev2?address=\(validAddress)"
        try await testNetworkClient.enqueueJSONResponse(
            url: accountURL,
            object: [
                "balance": 0,
                "tokens": [[
                    "tokenId": TronBalanceService.usdtTronContract,
                    "balance": "500000"
                ]]
            ]
        )
        try await testNetworkClient.enqueueJSONResponse(
            url: resourceURL,
            object: [
                "data": [
                    ["balance": 2_500_000],
                    ["balance": "1_500_000".replacingOccurrences(of: "_", with: "")]
                ]
            ]
        )

        let result = try await TronBalanceService.fetchBalances(for: validAddress)
        XCTAssertEqual(result.trxBalance, 4.0, accuracy: 0.0000001)
        XCTAssertEqual(result.tokenBalances.first(where: { $0.symbol == "USDT" })?.balance ?? 0, 0.5, accuracy: 0.0000001)
    }

    func testFetchBalancesFallsBackToTronScanTokenOverviewForTRXBalance() async throws {
        let accountURL = "https://apilist.tronscanapi.com/api/accountv2?address=\(validAddress)"
        let overviewURL = "https://apilist.tronscanapi.com/api/account/token_asset_overview?address=\(validAddress)"
        try await testNetworkClient.enqueueJSONResponse(
            url: accountURL,
            object: [
                "balance": 0,
                "tokens": [[
                    "tokenId": TronBalanceService.usdtTronContract,
                    "balance": "500000"
                ]]
            ]
        )
        try await testNetworkClient.enqueueJSONResponse(
            url: overviewURL,
            object: [
                "data": [[
                    "tokenId": "_",
                    "tokenName": "trx",
                    "tokenAbbr": "trx",
                    "tokenDecimal": 6,
                    "balance": "7500000"
                ]]
            ]
        )

        let result = try await TronBalanceService.fetchBalances(for: validAddress)
        XCTAssertEqual(result.trxBalance, 7.5, accuracy: 0.0000001)
        XCTAssertEqual(result.tokenBalances.first(where: { $0.symbol == "USDT" })?.balance ?? 0, 0.5, accuracy: 0.0000001)
    }

    func testFetchBalancesAcceptsAlreadyNormalizedDecimalTRXRowBalance() async throws {
        let url = "https://apilist.tronscanapi.com/api/accountv2?address=\(validAddress)"
        try await testNetworkClient.enqueueJSONResponse(
            url: url,
            object: [
                "balance": 0,
                "tokens": [
                    [
                        "tokenId": "_",
                        "tokenName": "TRON",
                        "tokenAbbr": "TRX",
                        "tokenDecimal": 6,
                        "balance": "3.25"
                    ]
                ]
            ]
        )

        let result = try await TronBalanceService.fetchBalances(for: validAddress)
        XCTAssertEqual(result.trxBalance, 3.25, accuracy: 0.0000001)
    }

    func testFetchBalancesParsesTronScanWithPriceTokensTRXRow() async throws {
        let url = "https://apilist.tronscanapi.com/api/accountv2?address=\(validAddress)"
        try await testNetworkClient.enqueueJSONResponse(
            url: url,
            object: [
                "balance": 0,
                "withPriceTokens": [
                    [
                        "tokenId": "_",
                        "tokenName": "TRON",
                        "tokenAbbr": "TRX",
                        "tokenDecimal": 6,
                        "balance": "4200000"
                    ],
                    [
                        "tokenId": TronBalanceService.usdtTronContract,
                        "tokenName": "Tether USD",
                        "tokenAbbr": "USDT",
                        "tokenDecimal": 6,
                        "balance": "1500000"
                    ]
                ]
            ]
        )

        let result = try await TronBalanceService.fetchBalances(for: validAddress)
        XCTAssertEqual(result.trxBalance, 4.2, accuracy: 0.0000001)
        XCTAssertEqual(result.tokenBalances.first(where: { $0.symbol == "USDT" })?.balance ?? 0, 1.5, accuracy: 0.0000001)
    }

    func testFetchBalancesFallsBackToTronGridWhenTronScanFails() async throws {
        let tronscan1 = "https://apilist.tronscanapi.com/api/accountv2?address=\(validAddress)"
        let tronscan2 = "https://apilist.tronscan.org/api/accountv2?address=\(validAddress)"
        let tronscan3 = "https://apilist.tronscan.io/api/accountv2?address=\(validAddress)"
        let tronGrid = "https://api.trongrid.io/v1/accounts/\(validAddress)"

        await testNetworkClient.enqueueFailure(url: tronscan1, code: .cannotConnectToHost)
        await testNetworkClient.enqueueFailure(url: tronscan2, code: .cannotConnectToHost)
        await testNetworkClient.enqueueFailure(url: tronscan3, code: .cannotConnectToHost)
        try await testNetworkClient.enqueueJSONResponse(
            url: tronGrid,
            object: [
                "data": [[
                    "balance": 3_500_000,
                    "trc20": [[TronBalanceService.usdtTronContract: "2500000"]]
                ]]
            ]
        )

        let result = try await TronBalanceService.fetchBalances(for: validAddress)
        XCTAssertEqual(result.trxBalance, 3.5, accuracy: 0.0000001)
        XCTAssertEqual(result.tokenBalances.first(where: { $0.symbol == "USDT" })?.balance ?? 0, 2.5, accuracy: 0.0000001)
    }

    func testFetchBalancesParsesTronGridNativeBalanceWhenReturnedAsString() async throws {
        let tronscan1 = "https://apilist.tronscanapi.com/api/accountv2?address=\(validAddress)"
        let tronscan2 = "https://apilist.tronscan.org/api/accountv2?address=\(validAddress)"
        let tronscan3 = "https://apilist.tronscan.io/api/accountv2?address=\(validAddress)"
        let tronGrid = "https://api.trongrid.io/v1/accounts/\(validAddress)"

        await testNetworkClient.enqueueFailure(url: tronscan1, code: .cannotConnectToHost)
        await testNetworkClient.enqueueFailure(url: tronscan2, code: .cannotConnectToHost)
        await testNetworkClient.enqueueFailure(url: tronscan3, code: .cannotConnectToHost)
        try await testNetworkClient.enqueueJSONResponse(
            url: tronGrid,
            object: [
                "data": [[
                    "balance": "4100000",
                    "trc20": [[TronBalanceService.usdtTronContract: "1250000"]]
                ]]
            ]
        )

        let result = try await TronBalanceService.fetchBalances(for: validAddress)
        XCTAssertEqual(result.trxBalance, 4.1, accuracy: 0.0000001)
        XCTAssertEqual(result.tokenBalances.first(where: { $0.symbol == "USDT" })?.balance ?? 0, 1.25, accuracy: 0.0000001)
    }

    func testFetchBalancesFallsBackToTronGridWalletAccountForNativeTRXBalance() async throws {
        let tronscan1 = "https://apilist.tronscanapi.com/api/accountv2?address=\(validAddress)"
        let tronscan2 = "https://apilist.tronscan.org/api/accountv2?address=\(validAddress)"
        let tronscan3 = "https://apilist.tronscan.io/api/accountv2?address=\(validAddress)"
        let tronGrid = "https://api.trongrid.io/v1/accounts/\(validAddress)"
        let tronGridAccountRPC = "https://api.trongrid.io/wallet/getaccount"

        await testNetworkClient.enqueueFailure(url: tronscan1, code: .cannotConnectToHost)
        await testNetworkClient.enqueueFailure(url: tronscan2, code: .cannotConnectToHost)
        await testNetworkClient.enqueueFailure(url: tronscan3, code: .cannotConnectToHost)
        try await testNetworkClient.enqueueJSONResponse(
            url: tronGrid,
            object: [
                "data": [[
                    "balance": 0,
                    "trc20": [[TronBalanceService.usdtTronContract: "2500000"]]
                ]]
            ]
        )
        try await testNetworkClient.enqueueJSONResponse(
            url: tronGridAccountRPC,
            object: [
                "balance": 0,
                "frozenV2": [
                    ["amount": 2_000_000],
                    ["amount": "1000000"]
                ]
            ]
        )

        let result = try await TronBalanceService.fetchBalances(for: validAddress)
        XCTAssertEqual(result.trxBalance, 3.0, accuracy: 0.0000001)
        XCTAssertEqual(result.tokenBalances.first(where: { $0.symbol == "USDT" })?.balance ?? 0, 2.5, accuracy: 0.0000001)
    }

    func testFetchBalancesPrefersTronGridWhenTronScanSucceedsButReturnsZeroNativeTRX() async throws {
        let tronScan = "https://apilist.tronscanapi.com/api/accountv2?address=\(validAddress)"
        let tronGrid = "https://api.trongrid.io/v1/accounts/\(validAddress)"

        try await testNetworkClient.enqueueJSONResponse(
            url: tronScan,
            object: [
                "balance": 0,
                "tokens": [[
                    "tokenId": TronBalanceService.usdtTronContract,
                    "balance": "2000000"
                ]]
            ]
        )
        try await testNetworkClient.enqueueJSONResponse(
            url: tronGrid,
            object: [
                "data": [[
                    "balance": 4_250_000,
                    "trc20": [[TronBalanceService.usdtTronContract: "2000000"]]
                ]]
            ]
        )

        let result = try await TronBalanceService.fetchBalances(for: validAddress)
        XCTAssertEqual(result.trxBalance, 4.25, accuracy: 0.0000001)
        XCTAssertEqual(result.tokenBalances.first(where: { $0.symbol == "USDT" })?.balance ?? 0, 2.0, accuracy: 0.0000001)
    }

    func testFetchRecentHistoryClassifiesNativeOutgoingTransferAsSendWhenRawDataAddressesAreHex() async throws {
        let nativeURL = "https://api.trongrid.io/v1/accounts/\(ownerAddress)/transactions?limit=20&only_confirmed=false&order_by=block_timestamp,desc&visible=true"
        let trc20URL = "https://api.trongrid.io/v1/accounts/\(ownerAddress)/transactions/trc20?limit=20&contract_address=\(TronBalanceService.usdtTronContract)&only_confirmed=false&order_by=block_timestamp,desc"

        try await testNetworkClient.enqueueJSONResponse(
            url: nativeURL,
            object: [
                "data": [[
                    "txID": "native-send-hash",
                    "from": ownerAddress,
                    "to": counterpartyAddress,
                    "block_timestamp": 1_700_000_000_000 as Int64,
                    "raw_data": [
                        "contract": [[
                            "type": "TransferContract",
                            "parameter": [
                                "value": [
                                    "owner_address": "41aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                                    "to_address": "41bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                                    "amount": 1_500_000
                                ]
                            ]
                        ]]
                    ],
                    "ret": [["contractRet": "SUCCESS"]]
                ]]
            ]
        )
        try await testNetworkClient.enqueueJSONResponse(url: trc20URL, object: ["data": []])

        let result = await TronBalanceService.fetchRecentHistoryWithDiagnostics(for: ownerAddress, limit: 20)

        XCTAssertEqual(result.snapshots.count, 1)
        XCTAssertEqual(result.snapshots.first?.kind, .send)
        XCTAssertEqual(result.snapshots.first?.counterpartyAddress, counterpartyAddress)
        XCTAssertEqual(result.snapshots.first?.amount ?? 0, 1.5, accuracy: 0.0000001)
    }
}
