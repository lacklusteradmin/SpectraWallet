import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
struct CoinBadge: View {
    let assetIdentifier: String?
    let fallbackText: String
    let color: Color
    var size: CGFloat = 40
    @AppStorage(TokenIconPreferenceStore.defaultsKey) private var tokenIconPreferencesStorage = ""
    @AppStorage(TokenIconPreferenceStore.customImageRevisionDefaultsKey) private var tokenIconCustomImageRevision = 0
    private var resolvedAssetIdentifier: String {
        if let assetIdentifier { return Coin.normalizedIconIdentifier(assetIdentifier) }
        return "generic:\(fallbackText.lowercased())"
    }
    private var tokenIconAssetName: String? {
        if let nativeDescriptor = Coin.nativeChainIconDescriptor(forAssetIdentifier: resolvedAssetIdentifier) { return nativeDescriptor.assetName }
        return TokenVisualRegistryEntry.entry(matchingAssetIdentifier: resolvedAssetIdentifier)?.assetName
    }
    private var preferredIconStyle: TokenIconStyle { TokenIconPreferenceStore.preference(for: resolvedAssetIdentifier, storage: tokenIconPreferencesStorage) }
    var body: some View {
        ZStack {
            if preferredIconStyle == .customPhoto, let customImage = customTokenImage { Image(uiImage: customImage).resizable().interpolation(.high).scaledToFit().frame(width: size, height: size) } else if preferredIconStyle == .artwork, let assetName = tokenIconAssetName, let bundleImage = BundleImageLoader.image(named: assetName) { Image(uiImage: bundleImage).resizable().interpolation(.high).scaledToFit().frame(width: size, height: size) } else {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    ).frame(width: size, height: size)
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 1).frame(width: size, height: size)
                Circle().fill(Color.white.opacity(0.18)).frame(width: size * 0.38, height: size * 0.38).offset(x: -size * 0.16, y: -size * 0.16)
                Text(fallbackText).font(.system(size: size * 0.3, weight: .black, design: .rounded)).foregroundColor(.white)
            }}.shadow(color: color.opacity(0.18), radius: 6, y: 3)
    }
    private var customTokenImage: UIImage? {
#if canImport(UIKit)
        _ = tokenIconCustomImageRevision
        return TokenIconImageStore.image(for: resolvedAssetIdentifier)
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
        }}
}
enum TokenIconPreferenceStore {
    static let defaultsKey = "settings.tokenIconPreferences.v1"
    static let customImageRevisionDefaultsKey = "settings.tokenIconCustomImageRevision.v1"
    static func preference(for identifier: String, storage: String) -> TokenIconStyle {
        let preferences = storedPreferences(from: storage)
        return preferences[identifier] ?? .artwork
    }
    static func updatePreference(_ preference: TokenIconStyle, for identifier: String, storage: String) -> String {
        var preferences = storedPreferences(from: storage)
        if preference == .artwork { preferences.removeValue(forKey: identifier) } else { preferences[identifier] = preference }
        return encodedStorage(from: preferences)
    }
    private static func storedPreferences(from storage: String) -> [String: TokenIconStyle] {
        guard let data = storage.data(using: .utf8), let rawPreferences = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return rawPreferences.reduce(into: [:]) { partialResult, entry in
            if let preference = TokenIconStyle(rawValue: entry.value) { partialResult[entry.key] = preference }}}
    private static func encodedStorage(from preferences: [String: TokenIconStyle]) -> String {
        guard !preferences.isEmpty else { return "" }
        let rawPreferences = preferences.mapValues(\.rawValue)
        guard let data = try? JSONEncoder().encode(rawPreferences), let encoded = String(data: data, encoding: .utf8) else { return "" }
        return encoded
    }
}
enum TokenIconImageStore {
    static let maximumUploadBytes = 3 * 1024 * 1024
#if canImport(UIKit)
    private static let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 128
        return cache
    }()
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
            }}}
    static func hasCustomImage(for identifier: String) -> Bool {
        guard let url = customImageURL(for: identifier) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
#if canImport(UIKit)
    static func image(for identifier: String) -> UIImage? {
        let key = identifier as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        guard let url = customImageURL(for: identifier), FileManager.default.fileExists(atPath: url.path), let image = UIImage(contentsOfFile: url.path) else { return nil }
        imageCache.setObject(image, forKey: key)
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
        }}
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
        }}
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
    private static func customImageURL(for identifier: String) -> URL? { try? customIconDirectoryURL().appendingPathComponent(fileName(for: identifier)) }
    private static func customIconDirectoryURL() throws -> URL {
        let applicationSupportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return applicationSupportDirectory.appendingPathComponent("Spectra", isDirectory: true).appendingPathComponent("TokenIcons", isDirectory: true)
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
                Text(symbol).font(.caption).foregroundColor(.secondary)
            }}}
}
struct SpectraBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ZStack {
            LinearGradient(colors: backdropGradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color.red.opacity(0.45)).frame(width: 280, height: 280).blur(radius: 70).offset(x: -120, y: -220)
            Circle().fill(Color.orange.opacity(0.45)).frame(width: 240, height: 240).blur(radius: 65).offset(x: 100, y: -170)
            Circle().fill(Color.green.opacity(0.35)).frame(width: 230, height: 230).blur(radius: 70).offset(x: -140, y: 40)
            Circle().fill(Color.blue.opacity(0.4)).frame(width: 260, height: 260).blur(radius: 75).offset(x: 140, y: 120)
            Circle().fill(Color.purple.opacity(0.36)).frame(width: 250, height: 250).blur(radius: 80).offset(x: 0, y: 260)
        }.ignoresSafeArea()
    }
    private var backdropGradientColors: [Color] {
        if colorScheme == .light {
            return [
                Color(red: 0.96, green: 0.97, blue: 0.99), Color(red: 0.95, green: 0.96, blue: 0.98), Color(red: 0.93, green: 0.95, blue: 0.98)
            ]
        }
        return [
            Color(red: 0.08, green: 0.12, blue: 0.22), Color(red: 0.12, green: 0.08, blue: 0.18), Color(red: 0.04, green: 0.1, blue: 0.16)
        ]
    }
}
extension View {
    func spectraNumericTextLayout(minimumScaleFactor: CGFloat = 0.62) -> some View { lineLimit(1).minimumScaleFactor(minimumScaleFactor).allowsTightening(true) }
}
struct SpectraLogo: View {
    var size: CGFloat = 78
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(Color.white.opacity(0.08)).frame(width: size, height: size).background(
                    ZStack {
                        Circle().fill(Color.red.opacity(0.75)).frame(width: size * 0.7, height: size * 0.7).blur(radius: size * 0.14).offset(x: -size * 0.2, y: -size * 0.18)
                        Circle().fill(Color.yellow.opacity(0.72)).frame(width: size * 0.6, height: size * 0.6).blur(radius: size * 0.14).offset(x: size * 0.18, y: -size * 0.16)
                        Circle().fill(Color.green.opacity(0.62)).frame(width: size * 0.58, height: size * 0.58).blur(radius: size * 0.14).offset(x: -size * 0.16, y: size * 0.16)
                        Circle().fill(Color.blue.opacity(0.68)).frame(width: size * 0.62, height: size * 0.62).blur(radius: size * 0.15).offset(x: size * 0.2, y: size * 0.18)
                        Circle().fill(Color.purple.opacity(0.55)).frame(width: size * 0.52, height: size * 0.52).blur(radius: size * 0.16)
                    }
                ).overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                ).glassEffect(.regular.tint(.white.opacity(0.044)), in: .rect(cornerRadius: size * 0.28))
            Text("S").font(.system(size: size * 0.62, weight: .black, design: .rounded)).foregroundStyle(Color.primary).shadow(color: .black.opacity(0.18), radius: 8, y: 2).rotationEffect(.degrees(-8))
        }.shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }
}
