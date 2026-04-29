// Renders SVG files from the flat `resources/icons/` bundle directory into
// UIImage via a shared, long-lived WKWebView snapshot. iOS does not provide
// a public API to render SVG from arbitrary file URLs, so we delegate to
// WebKit. Earlier versions spawned a new WKWebView per render — each
// instance bootstraps its own WebContent process, and a boot-time warm-up
// of the icon set produced ~12 concurrent processes that thrashed the CPU
// and stalled main-thread UI. The current path keeps a single WebContent
// process alive and serializes renders through it.

import Foundation
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
