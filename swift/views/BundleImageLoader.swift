import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

// Loads chain/token images from the root `resources/icons/` folder via
// Bundle.main — no xcassets dependency. The icons folder lands in the iOS
// bundle via a PBXFileSystemSynchronizedRootGroup that references `../resources`.
//
// Lookup order in `image(named:)`:
//   1. Cached UIImage (a previously-decoded PNG OR a previously-rendered SVG snapshot).
//   2. Flat-bundle `<name>.svg` — rendered once via `SVGRenderer.render` (WKWebView
//      snapshot, async). The cache miss returns nil; callers should pre-warm
//      the cache via `warmRasterCache()` so this miss never happens at render time.
//   3. Flat-bundle `<name>.png` — synchronous fallback for icons that haven't
//      been migrated to SVG yet.
//
// On non-Apple targets, replace the UIKit branch with whatever image-loading
// API the platform provides; the on-disk layout (`resources/icons/{name}.{svg,png}`)
// stays identical.
enum BundleImageLoader {
    #if canImport(UIKit)
        private static let imageCache: NSCache<NSString, UIImage> = {
            let cache = NSCache<NSString, UIImage>()
            cache.countLimit = 64
            // Bound by total pixel cost too — prevents the resident-memory
            // footprint from scaling linearly with countLimit when icons are
            // high-res bitmaps. 16 MB is plenty for 64 token icons at 256×256.
            cache.totalCostLimit = 16 * 1024 * 1024
            return cache
        }()
        private final class CachedURL {
            let url: URL?
            init(_ url: URL?) { self.url = url }
        }
        private static let urlCache = NSCache<NSString, CachedURL>()
    #endif

    private static func pngURL(forImageNamed name: String) -> URL? {
        #if canImport(UIKit)
            let key = "png:\(name)" as NSString
            if let cached = urlCache.object(forKey: key) { return cached.url }
        #endif
        let resolved = resolvedURL(forImageNamed: name, ext: "png")
        #if canImport(UIKit)
            urlCache.setObject(CachedURL(resolved), forKey: "png:\(name)" as NSString)
        #endif
        return resolved
    }

    /// SVG file URL for `name` if `<name>.svg` exists in the bundle. SVGs are
    /// rendered to UIImage via `SVGRenderer.render(svgURL:size:)` and cached.
    static func svgURL(forImageNamed name: String) -> URL? {
        #if canImport(UIKit)
            let key = "svg:\(name)" as NSString
            if let cached = urlCache.object(forKey: key) { return cached.url }
        #endif
        let resolved = resolvedURL(forImageNamed: name, ext: "svg")
        #if canImport(UIKit)
            urlCache.setObject(CachedURL(resolved), forKey: "svg:\(name)" as NSString)
        #endif
        return resolved
    }

    private static func resolvedURL(forImageNamed name: String, ext: String) -> URL? {
        // Xcode's PBXFileSystemSynchronizedRootGroup flattens the referenced
        // folder's contents into the bundle root, so icons/*.{ext} end up
        // at the top level. Ask Bundle first, then fall back to legacy subpaths.
        if let url = Bundle.main.url(forResource: name, withExtension: ext) { return url }
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        for subpath in ["icons", "Resources/icons"] {
            let candidate =
                resourceURL
                .appendingPathComponent(subpath, isDirectory: true)
                .appendingPathComponent("\(name).\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// Returns a UIImage by name. Resolution order:
    /// 1. UIImage cache (a previously-loaded PNG OR a previously-rendered SVG snapshot).
    /// 2. Bundle-flat `<name>.png`. If found, it's loaded synchronously and cached.
    /// Returns nil for SVG-only icons until the SVG cache is warmed via
    /// `warmRasterCache()`. CoinBadge displays the colored letter fallback in
    /// that interval, so SVG-only icons should be pre-warmed at app boot.
    static func image(named name: String) -> UIImage? {
        #if canImport(UIKit)
            let key = name as NSString
            if let cached = imageCache.object(forKey: key) { return cached }
            // PNG fallback. SVGs need an async render via `warmRasterCache`.
            guard let url = pngURL(forImageNamed: name), let image = UIImage(contentsOfFile: url.path) else { return nil }
            imageCache.setObject(image, forKey: key, cost: approximateByteCost(for: image))
            return image
        #else
            return nil
        #endif
    }

    /// Renders any SVG in the bundle that doesn't already have a PNG cached
    /// equivalent and stores the result in the UIImage cache. Call once at
    /// app boot — subsequent `image(named:)` calls become synchronous hits.
    @MainActor
    static func warmRasterCache(targetSize: CGFloat = 256) async {
        #if canImport(UIKit)
            guard let bundleURL = Bundle.main.resourceURL else { return }
            // Scan the flat icon directories for SVG files.
            let candidateDirs: [URL] = [
                bundleURL,
                bundleURL.appendingPathComponent("icons", isDirectory: true),
                bundleURL.appendingPathComponent("Resources/icons", isDirectory: true),
            ]
            var seen = Set<String>()
            for dir in candidateDirs {
                guard let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
                    continue
                }
                for file in contents where file.pathExtension.lowercased() == "svg" {
                    let stem = file.deletingPathExtension().lastPathComponent
                    guard seen.insert(stem).inserted else { continue }
                    if imageCache.object(forKey: stem as NSString) != nil { continue }
                    let size = CGSize(width: targetSize, height: targetSize)
                    if let rendered = await SVGRenderer.render(svgURL: file, size: size) {
                        imageCache.setObject(rendered, forKey: stem as NSString, cost: approximateByteCost(for: rendered))
                    }
                }
            }
        #endif
    }

    #if canImport(UIKit)
        private static func approximateByteCost(for image: UIImage) -> Int {
            let scale = image.scale
            return Int(image.size.width * scale * image.size.height * scale * 4)
        }
    #endif

    /// Returns true when an SVG OR PNG file exists in the flat bundle layout.
    static func hasImage(named name: String) -> Bool {
        svgURL(forImageNamed: name) != nil || pngURL(forImageNamed: name) != nil
    }
}

/// A SwiftUI view that renders a token image loaded from Resources/icons/.
/// Falls back to `nil` content when the image is unavailable so callers can provide their own fallback.
struct BundleTokenImage: View {
    let name: String
    var size: CGFloat = 40

    var body: some View {
        if let uiImage = BundleImageLoader.image(named: name) {
            Image(uiImage: uiImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
        }
    }
}
