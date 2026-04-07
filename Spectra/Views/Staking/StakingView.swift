import SwiftUI

struct StakingView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                SpectraBackdrop()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            SpectraLogo(size: 54)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Staking (Coming Soon)")
                                    .font(.title2.bold())
                                    .foregroundStyle(Color.primary)
                                Text("Stake assets while preserving transparent, decentralized consensus.")
                                    .foregroundStyle(Color.primary.opacity(0.76))
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular.tint(.white.opacity(0.033)), in: .rect(cornerRadius: 28))

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Why staking matters")
                                .font(.headline)
                                .foregroundStyle(Color.primary)
                            Text("Staking helps secure proof-of-stake networks by distributing validator power across many independent participants instead of relying on a centralized operator.")
                                .font(.subheadline)
                                .foregroundStyle(Color.primary.opacity(0.82))
                            Text("When many holders stake through decentralized validators, consensus remains more censorship-resistant, geographically distributed, and resilient to single points of failure.")
                                .font(.subheadline)
                                .foregroundStyle(Color.primary.opacity(0.82))
                            Text("Spectra will prioritize non-custodial staking workflows where you keep control of your keys and can choose how your stake supports network decentralization.")
                                .font(.subheadline)
                                .foregroundStyle(Color.primary.opacity(0.82))
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 28))
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Staking")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
