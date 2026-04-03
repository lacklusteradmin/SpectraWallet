import Foundation
import Combine

final class WalletDashboardState: ObservableObject {
    @Published var pinnedAssetSymbols: [String] = []
    @Published var pinOptionBySymbol: [String: DashboardPinOption] = [:]
    @Published var availablePinOptions: [DashboardPinOption] = []
    @Published var assetGroups: [DashboardAssetGroup] = []
    @Published var relevantPriceKeys: Set<String> = []
    @Published var supportedTokenEntriesBySymbol: [String: [TokenPreferenceEntry]] = [:]
}
