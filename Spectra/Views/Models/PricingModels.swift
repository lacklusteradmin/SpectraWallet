import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum PricingProvider: String, CaseIterable, Identifiable {
    case coinGecko = "CoinGecko"
    case binance = "Binance Public API"
    case coinbaseExchange = "Coinbase Exchange API"
    case coinPaprika = "CoinPaprika"
    case coinLore = "CoinLore"
    
    var id: String { rawValue }
}

enum FiatRateProvider: String, CaseIterable, Identifiable {
    case openER = "Open ER"
    case exchangeRateHost = "ExchangeRate.host"
    case frankfurter = "Frankfurter API"
    case fawazAhmed = "Fawaz Ahmed Currency API"

    var id: String { rawValue }
}

enum FiatCurrency: String, CaseIterable, Identifiable {
    case usd = "USD"
    case eur = "EUR"
    case gbp = "GBP"
    case jpy = "JPY"
    case cny = "CNY"
    case inr = "INR"
    case cad = "CAD"
    case aud = "AUD"
    case chf = "CHF"
    case brl = "BRL"
    case sgd = "SGD"
    case aed = "AED"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .usd: return "US Dollar (USD)"
        case .eur: return "Euro (EUR)"
        case .gbp: return "British Pound (GBP)"
        case .jpy: return "Japanese Yen (JPY)"
        case .cny: return "Chinese Yuan (CNY)"
        case .inr: return "Indian Rupee (INR)"
        case .cad: return "Canadian Dollar (CAD)"
        case .aud: return "Australian Dollar (AUD)"
        case .chf: return "Swiss Franc (CHF)"
        case .brl: return "Brazilian Real (BRL)"
        case .sgd: return "Singapore Dollar (SGD)"
        case .aed: return "UAE Dirham (AED)"
        }
    }

}

enum CoinGeckoService {
    private struct CoinGeckoEndpointAttempt {
        let baseURL: String
        let headerName: String?
        let queryItemName: String?
    }

    static func fetchQuotes(for ids: [String], apiKey: String) async throws -> [String: Double] {
        let normalizedIDs = Array(
            Set(
                ids.map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                }
                .filter { !$0.isEmpty }
            )
        ).sorted()
        guard !normalizedIDs.isEmpty else { return [:] }

        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let attempts: [CoinGeckoEndpointAttempt]
        if trimmedAPIKey.isEmpty {
            attempts = [
                CoinGeckoEndpointAttempt(
                    baseURL: ChainBackendRegistry.MarketDataRegistry.coinGeckoSimplePriceURL,
                    headerName: nil,
                    queryItemName: nil
                )
            ]
        } else {
            attempts = [
                CoinGeckoEndpointAttempt(
                    baseURL: "https://pro-api.coingecko.com/api/v3/simple/price",
                    headerName: "x-cg-pro-api-key",
                    queryItemName: "x_cg_pro_api_key"
                ),
                CoinGeckoEndpointAttempt(
                    baseURL: ChainBackendRegistry.MarketDataRegistry.coinGeckoSimplePriceURL,
                    headerName: "x-cg-demo-api-key",
                    queryItemName: "x_cg_demo_api_key"
                )
            ]
        }

        var lastError: Error = URLError(.badServerResponse)
        for attempt in attempts {
            var components = URLComponents(string: attempt.baseURL)
            var queryItems = [
                URLQueryItem(name: "ids", value: normalizedIDs.joined(separator: ",")),
                URLQueryItem(name: "vs_currencies", value: "usd")
            ]
            if let queryItemName = attempt.queryItemName, !trimmedAPIKey.isEmpty {
                queryItems.append(URLQueryItem(name: queryItemName, value: trimmedAPIKey))
            }
            components?.queryItems = queryItems

            guard let url = components?.url else {
                lastError = URLError(.badURL)
                continue
            }

            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Spectra", forHTTPHeaderField: "User-Agent")
            if let headerName = attempt.headerName, !trimmedAPIKey.isEmpty {
                request.setValue(trimmedAPIKey, forHTTPHeaderField: headerName)
            }

            do {
                let (data, response) = try await ProviderHTTP.data(
                    for: request,
                    profile: .chainRead
                )
                guard let httpResponse = response as? HTTPURLResponse,
                      (200 ..< 300).contains(httpResponse.statusCode) else {
                    lastError = URLError(.badServerResponse)
                    continue
                }

                let decoded = try JSONDecoder().decode([String: [String: Double]].self, from: data)
                let prices = decoded.reduce(into: [String: Double]()) { result, entry in
                    if let usdPrice = entry.value["usd"] {
                        result[entry.key.lowercased()] = usdPrice
                    }
                }
                if !prices.isEmpty {
                    return prices
                }
                lastError = URLError(.zeroByteResource)
            } catch {
                lastError = error
            }
        }

        throw lastError
    }
}

private struct BinanceTickerPriceResponse: Decodable {
    let symbol: String
    let price: String
}

private struct CoinbaseExchangeRatesEnvelope: Decodable {
    struct Payload: Decodable {
        let rates: [String: String]
    }

    let data: Payload
}

private struct CoinPaprikaTicker: Decodable {
    struct Quotes: Decodable {
        struct USD: Decodable {
            let price: Double?
        }

        let usd: USD?

        enum CodingKeys: String, CodingKey {
            case usd = "USD"
        }
    }

    let id: String
    let name: String
    let symbol: String
    let quotes: Quotes?
}

private struct CoinLoreTickersResponse: Decodable {
    let data: [CoinLoreTicker]
}

private struct CoinLoreTicker: Decodable {
    let id: String
    let symbol: String
    let name: String
    let nameid: String
    let priceUSD: String

    enum CodingKeys: String, CodingKey {
        case id
        case symbol
        case name
        case nameid
        case priceUSD = "price_usd"
    }
}

enum LivePriceService {
    static func fetchQuotes(for coins: [Coin], provider: PricingProvider, coinGeckoAPIKey: String) async throws -> [String: Double] {
        switch provider {
        case .coinGecko:
            return try await fetchCoinGeckoQuotes(for: coins, apiKey: coinGeckoAPIKey)
        case .binance:
            return try await fetchBinanceQuotes(for: coins)
        case .coinbaseExchange:
            return try await fetchCoinbaseExchangeQuotes(for: coins)
        case .coinPaprika:
            return try await fetchCoinPaprikaQuotes(for: coins)
        case .coinLore:
            return try await fetchCoinLoreQuotes(for: coins)
        }
    }

    private static func fetchCoinGeckoQuotes(for coins: [Coin], apiKey: String) async throws -> [String: Double] {
        let grouped = Dictionary(grouping: coins.compactMap { coin -> (String, Coin)? in
            let normalizedID = coin.coinGeckoID
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !normalizedID.isEmpty else { return nil }
            return (normalizedID, coin)
        }, by: \.0)
        guard !grouped.isEmpty else { return [:] }

        let fetched = try await CoinGeckoService.fetchQuotes(for: grouped.keys.sorted(), apiKey: apiKey)
        var resolved: [String: Double] = [:]
        for (id, price) in fetched {
            for (_, coin) in grouped[id] ?? [] {
                resolved[coin.holdingKey] = price
            }
        }
        return resolved
    }

    private static func fetchBinanceQuotes(for coins: [Coin]) async throws -> [String: Double] {
        let stable = stablecoinQuotes(for: coins)
        guard let url = URL(string: ChainBackendRegistry.MarketDataRegistry.binanceTickerPriceURL) else {
            throw URLError(.badURL)
        }
        let data = try await fetchMarketData(from: url)
        let decoded = try JSONDecoder().decode([BinanceTickerPriceResponse].self, from: data)
        let priceBySymbol: [String: Double] = Dictionary(uniqueKeysWithValues: decoded.compactMap { ticker -> (String, Double)? in
            guard let price = Double(ticker.price), price > 0 else { return nil }
            return (ticker.symbol.uppercased(), price)
        })

        var resolved = stable
        for coin in coins where resolved[coin.holdingKey] == nil {
            let symbol = coin.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let candidates = ["\(symbol)USDT", "\(symbol)FDUSD", "\(symbol)USDC"]
            if let candidate = candidates.first(where: { priceBySymbol[$0] != nil }),
               let price = priceBySymbol[candidate] {
                resolved[coin.holdingKey] = price
            }
        }
        return resolved
    }

    private static func fetchCoinbaseExchangeQuotes(for coins: [Coin]) async throws -> [String: Double] {
        let stable = stablecoinQuotes(for: coins)
        guard let url = URL(string: ChainBackendRegistry.MarketDataRegistry.coinbaseExchangeRatesURL) else {
            throw URLError(.badURL)
        }
        let data = try await fetchMarketData(from: url)
        let decoded = try JSONDecoder().decode(CoinbaseExchangeRatesEnvelope.self, from: data)

        var resolved = stable
        for coin in coins where resolved[coin.holdingKey] == nil {
            let symbol = coin.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard let rawRate = decoded.data.rates[symbol],
                  let rate = Double(rawRate),
                  rate > 0 else {
                continue
            }
            resolved[coin.holdingKey] = 1.0 / rate
        }
        return resolved
    }

    private static func fetchCoinPaprikaQuotes(for coins: [Coin]) async throws -> [String: Double] {
        let stable = stablecoinQuotes(for: coins)
        guard let url = URL(string: ChainBackendRegistry.MarketDataRegistry.coinPaprikaTickersURL) else {
            throw URLError(.badURL)
        }
        let data = try await fetchMarketData(from: url)
        let decoded = try JSONDecoder().decode([CoinPaprikaTicker].self, from: data)

        let byID = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
        var bySymbol: [String: CoinPaprikaTicker] = [:]
        for ticker in decoded {
            let symbol = ticker.symbol.uppercased()
            if bySymbol[symbol] == nil {
                bySymbol[symbol] = ticker
            }
        }

        var resolved = stable
        for coin in coins where resolved[coin.holdingKey] == nil {
            if let id = coinPaprikaID(for: coin),
               let ticker = byID[id],
               let price = ticker.quotes?.usd?.price,
               price > 0 {
                resolved[coin.holdingKey] = price
                continue
            }
            if let ticker = bySymbol[coin.symbol.uppercased()],
               let price = ticker.quotes?.usd?.price,
               price > 0 {
                resolved[coin.holdingKey] = price
            }
        }
        return resolved
    }

    private static func fetchCoinLoreQuotes(for coins: [Coin]) async throws -> [String: Double] {
        let stable = stablecoinQuotes(for: coins)
        guard let url = URL(string: ChainBackendRegistry.MarketDataRegistry.coinLoreTickersURL) else {
            throw URLError(.badURL)
        }
        let data = try await fetchMarketData(from: url)
        let decoded = try JSONDecoder().decode(CoinLoreTickersResponse.self, from: data)

        let byNameID = Dictionary(uniqueKeysWithValues: decoded.data.map { ($0.nameid.lowercased(), $0) })
        var bySymbol: [String: CoinLoreTicker] = [:]
        for ticker in decoded.data {
            let symbol = ticker.symbol.uppercased()
            if bySymbol[symbol] == nil {
                bySymbol[symbol] = ticker
            }
        }

        var resolved = stable
        for coin in coins where resolved[coin.holdingKey] == nil {
            let geckoID = coin.coinGeckoID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let ticker = byNameID[coinLoreNameID(for: geckoID)] ?? bySymbol[coin.symbol.uppercased()]
            guard let ticker,
                  let price = Double(ticker.priceUSD),
                  price > 0 else {
                continue
            }
            resolved[coin.holdingKey] = price
        }
        return resolved
    }

    private static func stablecoinQuotes(for coins: [Coin]) -> [String: Double] {
        var resolved: [String: Double] = [:]
        for coin in coins {
            if isUSDStablecoin(coin.symbol) {
                resolved[coin.holdingKey] = 1.0
            }
        }
        return resolved
    }

    private static func isUSDStablecoin(_ symbol: String) -> Bool {
        let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return ["USDT", "USDC", "DAI", "FDUSD", "TUSD", "BUSD", "USDE", "PYUSD", "USDS", "USDD", "USDG", "USD1"].contains(normalized)
    }

    private static func coinPaprikaID(for coin: Coin) -> String? {
        let normalizedGeckoID = coin.coinGeckoID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let idByGeckoID: [String: String] = [
            "bitcoin": "btc-bitcoin",
            "ethereum": "eth-ethereum",
            "optimism": "op-optimism",
            "binancecoin": "bnb-binance-coin",
            "bitcoin-cash": "bch-bitcoin-cash",
            "bitcoin-cash-sv": "bsv-bitcoin-sv",
            "litecoin": "ltc-litecoin",
            "dogecoin": "doge-dogecoin",
            "cardano": "ada-cardano",
            "solana": "sol-solana",
            "tron": "trx-tron",
            "stellar": "xlm-stellar",
            "ripple": "xrp-xrp",
            "xrp": "xrp-xrp",
            "monero": "xmr-monero",
            "ethereum-classic": "etc-ethereum-classic",
            "sui": "sui-sui",
            "internet-computer": "icp-internet-computer",
            "near": "near-near-protocol",
            "polkadot": "dot-polkadot-token",
            "hyperliquid": "hype-hyperliquid",
            "tether": "usdt-tether",
            "usd-coin": "usdc-usd-coin",
            "dai": "dai-dai",
            "wrapped-bitcoin": "wbtc-wrapped-bitcoin",
            "chainlink": "link-chainlink",
            "uniswap": "uni-uniswap",
            "aave": "aave-aave",
            "shiba-inu": "shib-shiba-inu",
            "pepe": "pepe-pepe",
            "bitget-token": "bgb-bitget-token",
            "leo-token": "leo-unus-sed-leo",
            "cronos": "cro-cronos",
            "ethena-usde": "usde-ethena-usde",
            "ripple-usd": "rlusd-ripple-usd",
            "pax-gold": "paxg-pax-gold",
            "tether-gold": "xaut-tether-gold",
            "usdd": "usdd-usdd",
            "global-dollar": "usdg-global-dollar"
        ]
        if let id = idByGeckoID[normalizedGeckoID] {
            return id
        }

        let symbol = coin.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let idBySymbol: [String: String] = [
            "BTC": "btc-bitcoin",
            "ETH": "eth-ethereum",
            "OP": "op-optimism",
            "BNB": "bnb-binance-coin",
            "BCH": "bch-bitcoin-cash",
            "BSV": "bsv-bitcoin-sv",
            "LTC": "ltc-litecoin",
            "DOGE": "doge-dogecoin",
            "ADA": "ada-cardano",
            "SOL": "sol-solana",
            "TRX": "trx-tron",
            "XLM": "xlm-stellar",
            "XRP": "xrp-xrp",
            "XMR": "xmr-monero",
            "ETC": "etc-ethereum-classic",
            "SUI": "sui-sui",
            "ICP": "icp-internet-computer",
            "NEAR": "near-near-protocol",
            "DOT": "dot-polkadot-token",
            "HYPE": "hype-hyperliquid",
            "USDT": "usdt-tether",
            "USDC": "usdc-usd-coin",
            "DAI": "dai-dai",
            "BGB": "bgb-bitget-token",
            "LEO": "leo-unus-sed-leo",
            "CRO": "cro-cronos",
            "USDE": "usde-ethena-usde",
            "RLUSD": "rlusd-ripple-usd",
            "PAXG": "paxg-pax-gold",
            "XAUT": "xaut-tether-gold",
            "USDD": "usdd-usdd",
            "USDG": "usdg-global-dollar"
        ]
        return idBySymbol[symbol]
    }

    private static func coinLoreNameID(for coinGeckoID: String) -> String {
        let nameIDByGeckoID: [String: String] = [
            "bitcoin": "bitcoin",
            "bitcoin-cash-sv": "bitcoin-cash-sv",
            "polkadot": "polkadot",
            "stellar": "stellar",
            "tron": "tron",
            "ripple": "ripple",
            "xrp": "ripple"
        ]
        return nameIDByGeckoID[coinGeckoID] ?? coinGeckoID
    }

    private static func fetchMarketData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Spectra", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await ProviderHTTP.data(
            for: request,
            profile: .chainRead
        )
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

private struct OpenERRatesResponse: Decodable {
    let rates: [String: Double]
}

private struct FrankfurterRatesResponse: Decodable {
    let rates: [String: Double]
}

private struct ExchangeRateHostLiveResponse: Decodable {
    let quotes: [String: Double]?
}

private struct FawazAhmedUSDRatesResponse: Decodable {
    let usd: [String: Double]
}

enum FiatRateService {
    static func fetchRates(from provider: FiatRateProvider, currencies: [FiatCurrency]) async throws -> [String: Double] {
        let targets = currencies.filter { $0 != .usd }
        switch provider {
        case .openER:
            return try await fetchOpenERRates(currencies: targets)
        case .exchangeRateHost:
            return try await fetchExchangeRateHostRates(currencies: targets)
        case .frankfurter:
            return try await fetchFrankfurterRates(currencies: targets)
        case .fawazAhmed:
            return try await fetchFawazAhmedRates(currencies: targets)
        }
    }

    private static func fetchOpenERRates(currencies: [FiatCurrency]) async throws -> [String: Double] {
        guard let url = URL(string: ChainBackendRegistry.MarketDataRegistry.openERLatestUSDURL) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await ProviderHTTP.sessionData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(OpenERRatesResponse.self, from: data)
        return filteredRates(decoded.rates, allowedCurrencies: currencies)
    }

    private static func fetchFrankfurterRates(currencies: [FiatCurrency]) async throws -> [String: Double] {
        var components = URLComponents(string: ChainBackendRegistry.MarketDataRegistry.frankfurterLatestURL)
        components?.queryItems = [
            URLQueryItem(name: "from", value: "USD"),
            URLQueryItem(name: "to", value: currencies.map(\.rawValue).joined(separator: ","))
        ]
        guard let url = components?.url else {
            throw URLError(.badURL)
        }
        let (data, response) = try await ProviderHTTP.sessionData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(FrankfurterRatesResponse.self, from: data)
        return filteredRates(decoded.rates, allowedCurrencies: currencies)
    }

    private static func fetchExchangeRateHostRates(currencies: [FiatCurrency]) async throws -> [String: Double] {
        var components = URLComponents(string: ChainBackendRegistry.MarketDataRegistry.exchangeRateHostLiveURL)
        components?.queryItems = [
            URLQueryItem(name: "source", value: "USD"),
            URLQueryItem(name: "currencies", value: currencies.map(\.rawValue).joined(separator: ","))
        ]
        guard let url = components?.url else {
            throw URLError(.badURL)
        }
        let (data, response) = try await ProviderHTTP.sessionData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(ExchangeRateHostLiveResponse.self, from: data)
        let quotes = decoded.quotes ?? [:]
        return Dictionary(uniqueKeysWithValues: currencies.compactMap { currency in
            guard let rate = quotes["USD\(currency.rawValue)"] else { return nil }
            return (currency.rawValue, rate)
        })
    }

    private static func fetchFawazAhmedRates(currencies: [FiatCurrency]) async throws -> [String: Double] {
        guard let url = URL(string: ChainBackendRegistry.MarketDataRegistry.fawazAhmedUSDRatesURL) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await ProviderHTTP.sessionData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(FawazAhmedUSDRatesResponse.self, from: data)
        let normalized = Dictionary(uniqueKeysWithValues: decoded.usd.map { ($0.key.uppercased(), $0.value) })
        return filteredRates(normalized, allowedCurrencies: currencies)
    }

    private static func filteredRates(_ rates: [String: Double], allowedCurrencies: [FiatCurrency]) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: allowedCurrencies.compactMap { currency in
            guard let rate = rates[currency.rawValue], rate > 0 else { return nil }
            return (currency.rawValue, rate)
        })
    }
}
