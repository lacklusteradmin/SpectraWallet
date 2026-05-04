import Foundation
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

/// A SwiftUI view that renders a token image from Assets.xcassets.
/// Falls back to `nil` content when the image is unavailable so callers can provide their own fallback.
struct BundleTokenImage: View {
    let name: String
    var size: CGFloat = 40

    var body: some View {
        if let uiImage = UIImage(named: name) {
            Image(uiImage: uiImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
        }
    }
}

// MARK: ─ (merged from views/IconUIHelpers.swift)

#if canImport(UIKit)
    import UIKit
#endif
/// Chain/token badge. Renders the bundled chain artwork when one exists;
/// otherwise falls back to a solid circle with the first letter of
/// `fallbackText`. No custom photos, no multi-letter disambiguation.
struct CoinBadge: View {
    let assetIdentifier: String?
    let fallbackText: String
    let color: Color
    var size: CGFloat = 40
    var body: some View {
        let identifier: String =
            assetIdentifier.map { Coin.normalizedIconIdentifier($0) } ?? "generic:\(fallbackText.lowercased())"
        let assetName: String? = {
            if let raw = assetIdentifier {
                if let direct = Coin.nativeIconAssetName(forAssetIdentifier: raw) { return direct }
                if raw.hasPrefix("native:") { return nil }
            }
            return TokenVisualRegistryEntry.entry(matchingAssetIdentifier: identifier)?.assetName
        }()
        let displayImage: UIImage? = assetName.flatMap { UIImage(named: $0) }
        return Group {
            if let displayImage {
                Image(uiImage: displayImage).resizable().interpolation(.high).scaledToFit().frame(width: size, height: size)
            } else {
                letterFallback
            }
        }.shadow(color: color.opacity(0.18), radius: 6, y: 3)
    }
    private var letterFallback: some View {
        let letter = fallbackText.first.map { String($0).uppercased() } ?? "?"
        return Circle().fill(
            LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
        ).frame(width: size, height: size).overlay {
            Text(letter).font(.system(size: size * 0.5, weight: .semibold, design: .rounded)).foregroundStyle(.white)
        }
    }
}
struct ChainToggleLabel: View {
    let title: String
    let symbol: String
    var assetIdentifier: String? = nil
    let color: Color
    var body: some View {
        HStack(spacing: 10) {
            CoinBadge(assetIdentifier: assetIdentifier, fallbackText: symbol, color: color, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(symbol).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
/// iOS 26 wallpaper-style backdrop. Rich gradient with soft chroma clouds
/// so `.glassEffect` has something meaningful to refract. Matches Apple's
/// own Liquid Glass hero surfaces (Weather, Wallet, Maps cards) — desaturated
/// corner-anchored color blobs over a deep gradient rather than painterly
/// rainbow splatters.
struct SpectraBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ZStack {
            LinearGradient(colors: backdropGradientColors, startPoint: .top, endPoint: .bottom)
            Circle().fill(chroma1).frame(width: 340, height: 340).blur(radius: 90).offset(x: -140, y: -260)
            Circle().fill(chroma2).frame(width: 320, height: 320).blur(radius: 100).offset(x: 160, y: -160)
            Circle().fill(chroma3).frame(width: 300, height: 300).blur(radius: 110).offset(x: -120, y: 220)
            Circle().fill(chroma4).frame(width: 360, height: 360).blur(radius: 120).offset(x: 180, y: 320)
        }.ignoresSafeArea()
    }
    private var chroma1: Color { colorScheme == .light ? Color.blue.opacity(0.18) : Color.indigo.opacity(0.38) }
    private var chroma2: Color { colorScheme == .light ? Color.pink.opacity(0.14) : Color.purple.opacity(0.32) }
    private var chroma3: Color { colorScheme == .light ? Color.mint.opacity(0.14) : Color.teal.opacity(0.28) }
    private var chroma4: Color { colorScheme == .light ? Color.orange.opacity(0.12) : Color.pink.opacity(0.22) }
    private var backdropGradientColors: [Color] {
        if colorScheme == .light {
            return [
                Color(red: 0.98, green: 0.98, blue: 1.00), Color(red: 0.95, green: 0.96, blue: 0.99),
            ]
        }
        return [
            Color(red: 0.05, green: 0.06, blue: 0.11), Color(red: 0.08, green: 0.06, blue: 0.14),
            Color(red: 0.04, green: 0.05, blue: 0.09),
        ]
    }
}
extension View {
    func spectraNumericTextLayout(minimumScaleFactor: CGFloat = 0.62) -> some View {
        lineLimit(1).minimumScaleFactor(minimumScaleFactor).allowsTightening(true)
    }
    /// iOS 26 Liquid Glass card fill. Routes all legacy `spectraCardFill`
    /// usages through a proper `.glassEffect` so every card in the app
    /// participates in the Liquid Glass design language — not a flat tinted
    /// rectangle. The subtle white tint gives the glass a visible edge
    /// without competing with the card's own content.
    func spectraCardFill(cornerRadius: CGFloat = 24) -> some View {
        glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: cornerRadius))
    }
}
struct SpectraLogo: View {
    var size: CGFloat = 78
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(Color.white.opacity(0.08)).frame(width: size, height: size)
                .background(
                    ZStack {
                        Circle().fill(Color.red.opacity(0.75)).frame(width: size * 0.7, height: size * 0.7).blur(radius: size * 0.14)
                            .offset(x: -size * 0.2, y: -size * 0.18)
                        Circle().fill(Color.yellow.opacity(0.72)).frame(width: size * 0.6, height: size * 0.6).blur(radius: size * 0.14)
                            .offset(x: size * 0.18, y: -size * 0.16)
                        Circle().fill(Color.green.opacity(0.62)).frame(width: size * 0.58, height: size * 0.58).blur(radius: size * 0.14)
                            .offset(x: -size * 0.16, y: size * 0.16)
                        Circle().fill(Color.blue.opacity(0.68)).frame(width: size * 0.62, height: size * 0.62).blur(radius: size * 0.15)
                            .offset(x: size * 0.2, y: size * 0.18)
                        Circle().fill(Color.purple.opacity(0.55)).frame(width: size * 0.52, height: size * 0.52).blur(radius: size * 0.16)
                    }
                ).overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                ).glassEffect(.regular.tint(.white.opacity(0.044)), in: .rect(cornerRadius: size * 0.28))
            Text("S").font(.system(size: size * 0.62, weight: .black, design: .rounded)).foregroundStyle(Color.primary).shadow(
                color: .black.opacity(0.18), radius: 8, y: 2
            ).rotationEffect(.degrees(-8))
        }.shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }
}
