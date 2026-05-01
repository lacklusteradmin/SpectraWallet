import Foundation
import SwiftUI

// MARK: ─ (merged from views/BundleImageLoader.swift)

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
    @State private var resolvedImage: UIImage?
    var body: some View {
        // Resolve once per body eval — this used to be a computed property
        // that recomputed (and re-hit the memoized icon-identifier Rust
        // helper) 3× per cell; locking to one `let` keeps a body eval at
        // one cache read.
        let identifier: String =
            assetIdentifier.map { Coin.normalizedIconIdentifier($0) } ?? "generic:\(fallbackText.lowercased())"
        let assetName: String? = {
            if let nativeDescriptor = Coin.nativeChainIconDescriptor(forAssetIdentifier: identifier) {
                return nativeDescriptor.assetName
            }
            return TokenVisualRegistryEntry.entry(matchingAssetIdentifier: identifier)?.assetName
        }()
        // Synchronous cache hit (PNG load, or previously-rendered SVG snapshot).
        // The async `.task` below promotes a cold SVG into the cache and bumps
        // `resolvedImage` so the body re-renders with the rendered bitmap.
        let syncImage: UIImage? = assetName.flatMap { BundleImageLoader.image(named: $0) }
        let displayImage = resolvedImage ?? syncImage
        return Group {
            if let displayImage {
                Image(uiImage: displayImage).resizable().interpolation(.high).scaledToFit().frame(width: size, height: size)
            } else {
                letterFallback
            }
        }.shadow(color: color.opacity(0.18), radius: 6, y: 3)
            .task(id: assetName) {
                guard let assetName else {
                    resolvedImage = nil
                    return
                }
                // If sync lookup already returned an image we're done.
                if BundleImageLoader.image(named: assetName) != nil { return }
                // Otherwise the only candidate is an unrendered SVG — render
                // it once via WKWebView and store the snapshot in the cache.
                resolvedImage = await BundleImageLoader.resolveImage(named: assetName)
            }
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

// MARK: ─ (merged from views/SVGRenderer.swift)

// Renders SVG files from the flat `resources/icons/` bundle directory into
// UIImage via a shared, long-lived WKWebView snapshot. iOS does not provide
// a public API to render SVG from arbitrary file URLs, so we delegate to
// WebKit. Earlier versions spawned a new WKWebView per render — each
// instance bootstraps its own WebContent process, and a boot-time warm-up
// of the icon set produced ~12 concurrent processes that thrashed the CPU
// and stalled main-thread UI. The current path keeps a single WebContent
// process alive and serializes renders through it.

#if canImport(UIKit)
    import UIKit
    import WebKit
#endif

#if canImport(UIKit)
    @MainActor
    enum SVGRenderer {
        private final class LoadObserver: NSObject, WKNavigationDelegate {
            var onFinish: (() -> Void)?
            func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onFinish?() }
            func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onFinish?() }
            func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
                onFinish?()
            }
        }

        // One WebView, one WebContent process, reused for every SVG.
        private static var sharedWebView: WKWebView?
        private static let sharedObserver = LoadObserver()
        // Serialize renders so two concurrent callers don't fight over the
        // shared web view's navigation state. Each render awaits the previous
        // one before starting.
        private static var renderQueue: Task<UIImage?, Never> = Task { nil }

        private static func ensureWebView(size: CGSize) -> WKWebView {
            if let existing = sharedWebView {
                existing.frame = CGRect(origin: .zero, size: size)
                return existing
            }
            let configuration = WKWebViewConfiguration()
            configuration.suppressesIncrementalRendering = true
            let webView = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: configuration)
            webView.isOpaque = false
            webView.backgroundColor = .clear
            webView.scrollView.backgroundColor = .clear
            webView.scrollView.isScrollEnabled = false
            webView.navigationDelegate = sharedObserver
            sharedWebView = webView
            return webView
        }

        /// Renders the SVG at `url` into a UIImage of the requested point size,
        /// at the device scale. Returns nil if WebKit can't load or snapshot.
        ///
        /// Concurrent callers are serialized so only one snapshot is in flight
        /// at a time — the underlying shared WKWebView holds one navigation
        /// state and can't multiplex requests.
        static func render(svgURL: URL, size: CGSize) async -> UIImage? {
            let previous = renderQueue
            let task = Task<UIImage?, Never> { @MainActor in
                _ = await previous.value
                return await performRender(svgURL: svgURL, size: size)
            }
            renderQueue = task
            return await task.value
        }

        private static func performRender(svgURL: URL, size: CGSize) async -> UIImage? {
            let scale = UITraitCollection.current.displayScale
            let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)
            let webView = ensureWebView(size: size)

            let html = """
                <!doctype html><html><head><meta charset="utf-8">
                <meta name="viewport" content="width=device-width,initial-scale=1.0">
                <style>html,body{margin:0;padding:0;background:transparent;}img{width:100vw;height:100vh;display:block;}</style>
                </head><body><img src="\(svgURL.lastPathComponent)"></body></html>
                """
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                var resumed = false
                sharedObserver.onFinish = {
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume()
                }
                webView.loadHTMLString(html, baseURL: svgURL.deletingLastPathComponent())
            }
            sharedObserver.onFinish = nil
            // One frame for the layout/paint to commit. 16ms (~one display frame)
            // is enough; the previous 50ms held the main actor unnecessarily.
            try? await Task.sleep(nanoseconds: 16_000_000)

            let snapshotConfig = WKSnapshotConfiguration()
            snapshotConfig.rect = CGRect(origin: .zero, size: size)
            snapshotConfig.snapshotWidth = NSNumber(value: Double(pixelSize.width / scale))
            return try? await webView.takeSnapshot(configuration: snapshotConfig)
        }
    }
#endif
