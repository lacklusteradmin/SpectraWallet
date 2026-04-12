import Foundation
import SolanaSwift

struct SolanaSPLTokenBalanceSnapshot: Equatable {
    let mintAddress: String
    let sourceTokenAccountAddress: String
    let symbol: String
    let name: String
    let tokenStandard: String
    let decimals: Int
    let balance: Double
    let marketDataID: String
    let coinGeckoID: String
}

struct SolanaPortfolioSnapshot: Equatable {
    let nativeBalance: Double
    let tokenBalances: [SolanaSPLTokenBalanceSnapshot]
}

enum SolanaBalanceService {
    static func endpointCatalog() -> [String] {
        SolanaProvider.balanceEndpointCatalog()
    }

    static func diagnosticsChecks() -> [(endpoint: String, probeURL: String)] {
        SolanaProvider.diagnosticsChecks()
    }

    struct KnownTokenMetadata {
        let symbol: String
        let name: String
        let decimals: Int
        let marketDataID: String
        let coinGeckoID: String
    }

    static let usdtMintAddress = PublicKey.usdtMint.base58EncodedString
    static let usdcMintAddress = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
    static let pyusdMintAddress = "2b1kV6DkPAnxd5ixfnxCpjxmKwqjjaYmCZfHsFu24GXo"
    static let usdgMintAddress = "2u1tszSeqZ3qBWF3uNGPFc8TzMk2tdiwknnRMWGWjGWH"
    static let usd1MintAddress = "USD1ttGY1N17NEEHLmELoaybftRBUSErhqYiQzvEmuB"
    static let linkMintAddress = "LinkhB3afbBKb2EQQu7s7umdZceV3wcvAUJhQAfQ23L"
    static let wlfiMintAddress = "WLFinEv6ypjkczcS83FZqFpgFZYwQXutRbxGe7oC16g"
    static let jupMintAddress = "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN"
    static let bonkMintAddress = "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"

    static let knownTokenMetadataByMint: [String: KnownTokenMetadata] = [
        PublicKey.usdtMint.base58EncodedString: KnownTokenMetadata(
            symbol: "USDT",
            name: "Tether USD",
            decimals: 6,
            marketDataID: "825",
            coinGeckoID: "tether"
        ),
        usdcMintAddress: KnownTokenMetadata(
            symbol: "USDC",
            name: "USD Coin",
            decimals: 6,
            marketDataID: "3408",
            coinGeckoID: "usd-coin"
        ),
        pyusdMintAddress: KnownTokenMetadata(
            symbol: "PYUSD",
            name: "PayPal USD",
            decimals: 6,
            marketDataID: "27772",
            coinGeckoID: "paypal-usd"
        ),
        usdgMintAddress: KnownTokenMetadata(
            symbol: "USDG",
            name: "Global Dollar",
            decimals: 6,
            marketDataID: "0",
            coinGeckoID: "global-dollar"
        ),
        usd1MintAddress: KnownTokenMetadata(
            symbol: "USD1",
            name: "USD1",
            decimals: 6,
            marketDataID: "0",
            coinGeckoID: ""
        ),
        linkMintAddress: KnownTokenMetadata(
            symbol: "LINK",
            name: "Chainlink",
            decimals: 8,
            marketDataID: "1975",
            coinGeckoID: "chainlink"
        ),
        wlfiMintAddress: KnownTokenMetadata(
            symbol: "WLFI",
            name: "World Liberty Financial",
            decimals: 6,
            marketDataID: "0",
            coinGeckoID: ""
        ),
        jupMintAddress: KnownTokenMetadata(
            symbol: "JUP",
            name: "Jupiter",
            decimals: 6,
            marketDataID: "29210",
            coinGeckoID: "jupiter-exchange-solana"
        ),
        bonkMintAddress: KnownTokenMetadata(
            symbol: "BONK",
            name: "Bonk",
            decimals: 5,
            marketDataID: "23095",
            coinGeckoID: "bonk"
        )
    ]

    static func mintAddress(for symbol: String) -> String? {
        switch symbol.uppercased() {
        case "USDT":
            return usdtMintAddress
        case "USDC":
            return usdcMintAddress
        case "PYUSD":
            return pyusdMintAddress
        case "USDG":
            return usdgMintAddress
        case "USD1":
            return usd1MintAddress
        case "LINK":
            return linkMintAddress
        case "WLFI":
            return wlfiMintAddress
        case "JUP":
            return jupMintAddress
        case "BONK":
            return bonkMintAddress
        default:
            return nil
        }
    }

    static func isValidAddress(_ address: String) -> Bool {
        AddressValidation.isValidSolanaAddress(address)
    }
}
