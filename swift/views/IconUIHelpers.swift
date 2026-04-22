import Foundation
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif
@Observable
@MainActor
final class TokenIconImageRevision {
    static let shared = TokenIconImageRevision()
    private(set) var tick: Int = 0
    func bump() { tick += 1 }
    private init() {}
}
struct CoinBadge: View {
    let assetIdentifier: String?
    let fallbackText: String
    let color: Color
    var size: CGFloat = 40
    @Bindable private var preferences = TokenIconPreferences.shared
    var body: some View {
        // Resolve once per body eval — this used to be a computed property
        // that recomputed (and re-hit the memoized icon-identifier Rust
        // helper) 3× per cell; locking to one `let` keeps a body eval at
        // one cache read.
        let identifier: String =
            assetIdentifier.map(Coin.normalizedIconIdentifier) ?? "generic:\(fallbackText.lowercased())"
        let style = preferences.style(for: identifier)
        let assetName: String? = {
            if let nativeDescriptor = Coin.nativeChainIconDescriptor(forAssetIdentifier: identifier) {
                return nativeDescriptor.assetName
            }
            return TokenVisualRegistryEntry.entry(matchingAssetIdentifier: identifier)?.assetName
        }()
        return ZStack {
            if style == .customPhoto, let customImage = customTokenImage(for: identifier) {
                Image(uiImage: customImage).resizable().interpolation(.high).scaledToFit().frame(width: size, height: size)
            } else if style == .artwork, let assetName, let bundleImage = BundleImageLoader.image(named: assetName) {
                Image(uiImage: bundleImage).resizable().interpolation(.high).scaledToFit().frame(width: size, height: size)
            } else {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                ).frame(width: size, height: size)
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 1).frame(
                    width: size, height: size)
                Circle().fill(Color.white.opacity(0.18)).frame(width: size * 0.38, height: size * 0.38).offset(
                    x: -size * 0.16, y: -size * 0.16)
                Text(fallbackText).font(.system(size: size * 0.3, weight: .black, design: .rounded)).foregroundStyle(.white)
            }
        }.shadow(color: color.opacity(0.18), radius: 6, y: 3)
    }
    private func customTokenImage(for identifier: String) -> UIImage? {
        #if canImport(UIKit)
            _ = TokenIconImageRevision.shared.tick
            return TokenIconImageStore.image(for: identifier)
        #else
            return nil
        #endif
    }
}
enum TokenIconStyle: String, CaseIterable, Identifiable {
    case artwork
    case customPhoto
    case classicBadge
    var id: String { rawValue }
    var title: String {
        switch self {
        case .artwork: return "Artwork"
        case .customPhoto: return "Photo"
        case .classicBadge: return "Classic"
        }
    }
}
enum TokenIconPreferenceStore {
    static let defaultsKey = "settings.tokenIconPreferences.v1"
}
@Observable
@MainActor
final class TokenIconPreferences {
    static let shared = TokenIconPreferences()
    private var cache: [String: TokenIconStyle]
    private init() { self.cache = Self.load() }
    var isEmpty: Bool { cache.isEmpty }
    func style(for identifier: String) -> TokenIconStyle { cache[identifier] ?? .artwork }
    func setStyle(_ style: TokenIconStyle, for identifier: String) {
        if style == .artwork { cache.removeValue(forKey: identifier) } else { cache[identifier] = style }
        persist()
    }
    func resetAll() {
        cache = [:]
        UserDefaults.standard.removeObject(forKey: TokenIconPreferenceStore.defaultsKey)
    }
    func reloadFromStorage() { cache = Self.load() }
    private func persist() {
        guard !cache.isEmpty else {
            UserDefaults.standard.removeObject(forKey: TokenIconPreferenceStore.defaultsKey)
            return
        }
        let raw = cache.mapValues(\.rawValue)
        guard let data = try? JSONEncoder().encode(raw), let encoded = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(encoded, forKey: TokenIconPreferenceStore.defaultsKey)
    }
    private static func load() -> [String: TokenIconStyle] {
        guard let storage = UserDefaults.standard.string(forKey: TokenIconPreferenceStore.defaultsKey),
            let data = storage.data(using: .utf8),
            let raw = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return raw.reduce(into: [:]) { result, entry in
            if let style = TokenIconStyle(rawValue: entry.value) { result[entry.key] = style }
        }
    }
}
enum TokenIconImageStore {
    static let maximumUploadBytes = 3 * 1024 * 1024
    #if canImport(UIKit)
        private static let imageCache: NSCache<NSString, UIImage> = {
            let cache = NSCache<NSString, UIImage>()
            cache.countLimit = 32
            // Cost-bound the cache too — users typically have few custom icons,
            // but each one is a 256×256 RGBA UIImage (~256 KB decoded). 8 MB
            // ceiling keeps this cache from becoming a Jetsam-kill source.
            cache.totalCostLimit = 8 * 1024 * 1024
            return cache
        }()
        private static func approximateByteCost(for image: UIImage) -> Int {
            let scale = image.scale
            return Int(image.size.width * scale * image.size.height * scale * 4)
        }
    #endif
    enum IconError: LocalizedError {
        case imageTooLarge
        case unreadableImage
        case failedToWrite
        var errorDescription: String? {
            switch self {
            case .imageTooLarge: return "Selected images must be 3 MB or smaller."
            case .unreadableImage: return "The selected photo could not be read as an image."
            case .failedToWrite: return "The custom icon could not be saved."
            }
        }
    }
    static func hasCustomImage(for identifier: String) -> Bool {
        guard let url = customImageURL(for: identifier) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
    #if canImport(UIKit)
        static func image(for identifier: String) -> UIImage? {
            let key = identifier as NSString
            if let cached = imageCache.object(forKey: key) { return cached }
            guard let url = customImageURL(for: identifier), FileManager.default.fileExists(atPath: url.path),
                let image = UIImage(contentsOfFile: url.path)
            else { return nil }
            imageCache.setObject(image, forKey: key, cost: approximateByteCost(for: image))
            return image
        }
        static func saveImageData(_ data: Data, for identifier: String) throws {
            guard data.count <= maximumUploadBytes else { throw IconError.imageTooLarge }
            guard let sourceImage = UIImage(data: data) else { throw IconError.unreadableImage }
            let normalizedImage = resizedImage(from: sourceImage, targetSize: CGSize(width: 256, height: 256))
            guard let pngData = normalizedImage.pngData(), let url = customImageURL(for: identifier) else { throw IconError.failedToWrite }
            do {
                let directoryURL = try customIconDirectoryURL()
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                try pngData.write(to: url, options: .atomic)
                imageCache.removeObject(forKey: identifier as NSString)
            } catch {
                throw IconError.failedToWrite
            }
        }
        private static func resizedImage(from image: UIImage, targetSize: CGSize) -> UIImage {
            let renderer = UIGraphicsImageRenderer(size: targetSize)
            return renderer.image { _ in
                UIColor.clear.setFill()
                UIBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()
                let aspectRatio = min(targetSize.width / max(image.size.width, 1), targetSize.height / max(image.size.height, 1))
                let drawnSize = CGSize(width: image.size.width * aspectRatio, height: image.size.height * aspectRatio)
                let origin = CGPoint(
                    x: (targetSize.width - drawnSize.width) / 2, y: (targetSize.height - drawnSize.height) / 2
                )
                image.draw(in: CGRect(origin: origin, size: drawnSize))
            }
        }
    #endif
    static func removeImage(for identifier: String) {
        guard let url = customImageURL(for: identifier), FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
        #if canImport(UIKit)
            imageCache.removeObject(forKey: identifier as NSString)
        #endif
    }
    static func removeAllImages() {
        guard let directoryURL = try? customIconDirectoryURL(), FileManager.default.fileExists(atPath: directoryURL.path) else { return }
        try? FileManager.default.removeItem(at: directoryURL)
        #if canImport(UIKit)
            imageCache.removeAllObjects()
        #endif
    }
    private static func customImageURL(for identifier: String) -> URL? {
        try? customIconDirectoryURL().appendingPathComponent(fileName(for: identifier))
    }
    private static func customIconDirectoryURL() throws -> URL {
        let applicationSupportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return applicationSupportDirectory.appendingPathComponent("Spectra", isDirectory: true).appendingPathComponent(
            "TokenIcons", isDirectory: true)
    }
    private static func fileName(for identifier: String) -> String {
        let sanitizedMark = identifier.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
        return "\(sanitizedMark).png"
    }
}
struct ChainToggleLabel: View {
    let title: String
    let symbol: String
    let mark: String
    var assetIdentifier: String? = nil
    let color: Color
    var body: some View {
        HStack(spacing: 10) {
            CoinBadge(assetIdentifier: assetIdentifier, fallbackText: mark, color: color, size: 28)
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
