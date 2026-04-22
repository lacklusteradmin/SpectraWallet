import SwiftUI
struct StakingView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                SpectraBackdrop().ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(AppLocalization.string("Staking (Coming Soon)")).font(.title2.weight(.bold))
                            Text(AppLocalization.string("Stake assets while preserving transparent, decentralized consensus."))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                            .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 28))
                        VStack(alignment: .leading, spacing: 12) {
                            Text(AppLocalization.string("Why staking matters")).font(.headline)
                            Text(
                                AppLocalization.string(
                                    "Staking helps secure proof-of-stake networks by distributing validator power across many independent participants instead of relying on a centralized operator."
                                )
                            ).font(.subheadline).foregroundStyle(.secondary)
                            Text(
                                AppLocalization.string(
                                    "When many holders stake through decentralized validators, consensus remains more censorship-resistant, geographically distributed, and resilient to single points of failure."
                                )
                            ).font(.subheadline).foregroundStyle(.secondary)
                            Text(
                                AppLocalization.string(
                                    "Spectra will prioritize non-custodial staking workflows where you keep control of your keys and can choose how your stake supports network decentralization."
                                )
                            ).font(.subheadline).foregroundStyle(.secondary)
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                            .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 28))
                    }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
                }
            }.navigationTitle(AppLocalization.string("Staking")).navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}
