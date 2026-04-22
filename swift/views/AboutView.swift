import Foundation
import SwiftUI
struct AboutView: View {
    @State private var isAnimatingHero = false
    private var copy: SettingsContentCopy { .current }
    var body: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 22) {
                    aboutHero
                    aboutCard(title: copy.aboutEthosTitle, lines: copy.aboutEthosLines)
                    aboutNarrativeCard
                }.padding(20)
            }
        }.navigationTitle(AppLocalization.string("About Spectra")).navigationBarTitleDisplayMode(.inline).onAppear {
            isAnimatingHero = true
        }.onDisappear {
            // Stop the infinite rotation so the GPU isn't animating an
            // off-screen layer when the user navigates away from About.
            isAnimatingHero = false
        }
    }
    private var aboutHero: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(
                    AngularGradient(
                        colors: [
                            .red.opacity(0.85), .orange.opacity(0.92), .yellow.opacity(0.9), .green.opacity(0.82), .blue.opacity(0.82),
                            .indigo.opacity(0.82), .pink.opacity(0.88), .red.opacity(0.85),
                        ], center: .center
                    )
                ).frame(width: 220, height: 220).blur(radius: 26).rotationEffect(.degrees(isAnimatingHero ? 360 : 0)).animation(
                    .linear(duration: 18).repeatForever(autoreverses: false), value: isAnimatingHero)
                Circle().fill(Color.white.opacity(0.08)).frame(width: 178, height: 178).background(.ultraThinMaterial, in: Circle())
                SpectraLogo(size: 96)
            }
            VStack(spacing: 8) {
                Text(copy.aboutTitle).font(.largeTitle.weight(.bold)).foregroundStyle(Color.primary)
                Text(copy.aboutSubtitle).font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity)
        }.padding(24).spectraBubbleFill().glassEffect(.regular.tint(.white.opacity(0.033)), in: .rect(cornerRadius: 30))
    }
    private var aboutNarrativeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(copy.aboutNarrativeTitle).font(.headline).foregroundStyle(Color.primary)
            ForEach(copy.aboutNarrativeParagraphs, id: \.self) { paragraph in
                Text(paragraph).font(.subheadline).foregroundStyle(.secondary)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).spectraBubbleFill().glassEffect(
            .regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 28))
    }
    private func aboutCard(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline).foregroundStyle(Color.primary)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(Color.primary.opacity(0.5)).frame(width: 6, height: 6).padding(.top, 7)
                    Text(line).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).spectraBubbleFill().glassEffect(
            .regular.tint(.white.opacity(0.028)), in: .rect(cornerRadius: 28))
    }
}
