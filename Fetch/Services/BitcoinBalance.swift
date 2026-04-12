import Foundation

enum BitcoinNetworkMode: String, CaseIterable, Identifiable, Codable {
    case mainnet
    case testnet
    case testnet4
    case signet

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mainnet:  return "Mainnet"
        case .testnet:  return "Testnet"
        case .testnet4: return "Testnet4"
        case .signet:   return "Signet"
        }
    }
}

struct BitcoinHistorySnapshot: Equatable {
    let txid: String
    let amountBTC: Double
    let kind: TransactionKind
    let status: TransactionStatus
    let counterpartyAddress: String
    let blockHeight: Int?
    let createdAt: Date
}

struct BitcoinHistoryPage {
    let snapshots: [BitcoinHistorySnapshot]
    let nextCursor: String?
    let sourceUsed: String
}


enum BitcoinBalanceService {
    static func fetchBalance(for address: String, networkMode: BitcoinNetworkMode = .mainnet) async throws -> Double {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty,
              let encodedAddress = trimmedAddress.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw URLError(.badURL)
        }
        return try await EsploraProvider.runWithFallback(baseURLs: EsploraProvider.runtimeBaseURLs(for: networkMode)) { baseURL in
            guard let url = EsploraProvider.url(baseURL: baseURL, path: "/address/\(encodedAddress)") else {
                throw URLError(.badURL)
            }
            let (data, response) = try await fetchData(from: url)
            guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let decoded = try JSONDecoder().decode(EsploraProvider.AddressResponse.self, from: data)
            let funded = decoded.chainStats.fundedTXOSum + decoded.mempoolStats.fundedTXOSum
            let spent = decoded.chainStats.spentTXOSum + decoded.mempoolStats.spentTXOSum
            let satoshis = max(0, funded - spent)
            return Double(satoshis) / 100_000_000
        }
    }

    static func fetchTransactionStatus(txid: String, networkMode: BitcoinNetworkMode = .mainnet) async throws -> EsploraProvider.TransactionStatus {
        let trimmedTXID = txid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTXID.isEmpty,
              let encodedTXID = trimmedTXID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw URLError(.badURL)
        }
        return try await EsploraProvider.runWithFallback(baseURLs: EsploraProvider.runtimeBaseURLs(for: networkMode)) { baseURL in
            guard let url = EsploraProvider.url(baseURL: baseURL, path: "/tx/\(encodedTXID)/status") else {
                throw URLError(.badURL)
            }
            let (data, response) = try await fetchData(from: url)
            guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }
            return try JSONDecoder().decode(EsploraProvider.TransactionStatus.self, from: data)
        }
    }

    private static func fetchData(from url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Spectra", forHTTPHeaderField: "User-Agent")
        return try await ProviderHTTP.data(for: request, profile: .chainRead)
    }

}
