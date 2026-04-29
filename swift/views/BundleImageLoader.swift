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
// Heating-defence layers (added after diagnosing CPU heat from the SVG path):
//   - `warmRasterCache()` is gated to run **once per process lifetime** via an
//     atomic flag. AppState recreation on lock/unlock no longer re-renders the
//     whole icon set.
//   - SVGs are rendered **serially with a small inter-render sleep**, not in
//     parallel — each WKWebView snapshot spawns a separate WebContent process,
//     and N parallel processes thrash CPU.
//   - `resolveImage(named:)` dedupes by name: concurrent callers asking for the
//     same icon share one WKWebView render task instead of each spinning up
//     their own.
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
        // Once-per-process gate so warm-up runs at most once per app launch
        // even if AppState is reinitialized (lock/unlock, scene-phase reset).
        nonisolated(unsafe) private static var didWarmCache = false
        private static let didWarmCacheLock = NSLock()
        // In-flight render dedupe: many cells can ask for the same SVG before
        // any of them has finished rendering. Sharing one Task per name turns
        // the N-concurrent-WKWebView storm into a single render.
        @MainActor private static var pendingRenders: [String: Task<UIImage?, Never>] = [:]
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

    /// Synchronous lookup. Returns the cached UIImage if present.
    ///
    /// **SVG-first semantics**: if an SVG file exists for `name` but its
    /// rendered snapshot isn't cached yet, this returns `nil` rather than
    /// loading a sibling PNG. That defers rendering to `resolveImage` and
    /// guarantees the SVG wins once available — without it, a sibling PNG
    /// would lock into the cache on first synchronous access and the SVG
    /// would never be rendered.
    ///
    /// PNG-only icons still load synchronously and cache normally.
    static func image(named name: String) -> UIImage? {
        #if canImport(UIKit)
            let key = name as NSString
            if let cached = imageCache.object(forKey: key) { return cached }
            // SVG exists but isn't cached yet → don't fall back to PNG; let the
            // async path render the SVG so it ends up in the cache.
            if svgURL(forImageNamed: name) != nil { return nil }
            guard let url = pngURL(forImageNamed: name), let image = UIImage(contentsOfFile: url.path) else { return nil }
            imageCache.setObject(image, forKey: key, cost: approximateByteCost(for: image))
            return image
        #else
            return nil
        #endif
    }

    /// Asynchronous lookup. Resolution order:
    /// 1. Cached UIImage (cache hit returns immediately).
    /// 2. Flat-bundle `<name>.svg` — rendered via `SVGRenderer`, cached.
    /// 3. Flat-bundle `<name>.png` — loaded synchronously, cached.
    /// Returns nil only when no icon file exists.
    ///
    /// **Dedupe**: if a render for `name` is already in flight, awaits the
    /// existing task instead of spawning a second WKWebView. Prevents the
    /// CPU storm when many cells ask for the same icon before any has finished.
    @MainActor
    static func resolveImage(named name: String, targetSize: CGFloat = 256) async -> UIImage? {
        #if canImport(UIKit)
            let key = name as NSString
            if let cached = imageCache.object(forKey: key) { return cached }
            if let inFlight = pendingRenders[name] { return await inFlight.value }
            let task = Task<UIImage?, Never> { @MainActor in
                await renderAndCache(name: name, targetSize: targetSize)
            }
            pendingRenders[name] = task
            let result = await task.value
            pendingRenders.removeValue(forKey: name)
            return result
        #else
            return nil
        #endif
    }

    #if canImport(UIKit)
        @MainActor
        private static func renderAndCache(name: String, targetSize: CGFloat) async -> UIImage? {
            let key = name as NSString
            if let cached = imageCache.object(forKey: key) { return cached }
            if let svg = svgURL(forImageNamed: name) {
                let size = CGSize(width: targetSize, height: targetSize)
                // Disk-cache check first — once an SVG has been rendered in any
                // prior session, we skip WebKit entirely on subsequent launches.
                if let diskCached = readDiskCachedImage(name: name, size: size) {
                    imageCache.setObject(diskCached, forKey: key, cost: approximateByteCost(for: diskCached))
                    return diskCached
                }
                if let rendered = await SVGRenderer.render(svgURL: svg, size: size) {
                    imageCache.setObject(rendered, forKey: key, cost: approximateByteCost(for: rendered))
                    writeDiskCachedImage(rendered, name: name, size: size)
                    return rendered
                }
            }
            if let url = pngURL(forImageNamed: name), let image = UIImage(contentsOfFile: url.path) {
                imageCache.setObject(image, forKey: key, cost: approximateByteCost(for: image))
                return image
            }
            return nil
        }

        private static let diskCacheDir: URL? = {
            guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
            let dir = caches.appendingPathComponent("SpectraIconCache", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }()

        private static func diskCacheURL(name: String, size: CGSize) -> URL? {
            guard let base = diskCacheDir else { return nil }
            let scale = UITraitCollection.current.displayScale
            let safeName = name.replacingOccurrences(of: "/", with: "_")
            return base.appendingPathComponent("\(safeName)@\(Int(size.width))x\(Int(scale)).png")
        }

        private static func readDiskCachedImage(name: String, size: CGSize) -> UIImage? {
            guard let url = diskCacheURL(name: name, size: size),
                FileManager.default.fileExists(atPath: url.path),
                let data = try? Data(contentsOf: url),
                let image = UIImage(data: data, scale: UITraitCollection.current.displayScale)
            else {
                return nil
            }
            return image
        }

        private static func writeDiskCachedImage(_ image: UIImage, name: String, size: CGSize) {
            guard let url = diskCacheURL(name: name, size: size), let data = image.pngData() else { return }
            // Hop off the main actor for the file write — small payload but
            // avoids holding main while the disk syscall completes.
            Task.detached(priority: .utility) {
                try? data.write(to: url, options: .atomic)
            }
        }
    #endif

    /// Pre-renders all bundle SVGs into the UIImage cache so the first badge
    /// render after launch is a cache hit. Idempotent across the process
    /// lifetime — calling it more than once (e.g. AppState reinit) is a no-op.
    /// Renders serially with a small inter-render sleep so concurrent
    /// WebContent processes don't pile up.
    @MainActor
    static func warmRasterCache(targetSize: CGFloat = 256) async {
        #if canImport(UIKit)
            // Once-per-process gate. A second AppState init shouldn't re-render
            // every SVG — that turned the icon set into a heat source on
            // lock/unlock cycles.
            let alreadyWarmed = didWarmCacheLock.withLock { () -> Bool in
                if didWarmCache { return true }
                didWarmCache = true
                return false
            }
            if alreadyWarmed { return }

            guard let bundleURL = Bundle.main.resourceURL else { return }
            let candidateDirs: [URL] = [
                bundleURL,
                bundleURL.appendingPathComponent("icons", isDirectory: true),
                bundleURL.appendingPathComponent("Resources/icons", isDirectory: true),
            ]
            var seen = Set<String>()
            var renderedCount = 0
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
                    renderedCount += 1
                    // Yield between renders so we don't spawn a new WebContent
                    // process every 50ms. Without this gap the boot sequence
                    // saturates the CPU briefly when many SVGs live in the bundle.
                    if renderedCount % 4 == 0 {
                        try? await Task.sleep(nanoseconds: 80_000_000)  // 80ms every 4 icons
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
