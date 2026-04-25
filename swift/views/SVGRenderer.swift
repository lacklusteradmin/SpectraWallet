// Renders SVG files from the flat `resources/icons/` bundle directory into
// UIImage via a short-lived WKWebView snapshot. iOS does not provide a public
// API to render SVG from arbitrary file URLs (UIImage(contentsOfFile:) is
// raster-only, UIImage(named:) only consults the Asset Catalog), so we delegate
// to Safari's WebKit engine for full SVG fidelity (clip-paths, gradients,
// color(display-p3 ...), etc.). The result is a plain UIImage that lives in
// the BundleImageLoader cache, so each SVG is rendered once per app launch.

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

        /// Renders the SVG at `url` into a UIImage of the requested point size,
        /// at the device scale. Returns nil if WebKit can't load or snapshot.
        static func render(svgURL: URL, size: CGSize) async -> UIImage? {
            let scale = UIScreen.main.scale
            let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)
            let configuration = WKWebViewConfiguration()
            configuration.suppressesIncrementalRendering = true
            let webView = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: configuration)
            webView.isOpaque = false
            webView.backgroundColor = .clear
            webView.scrollView.backgroundColor = .clear
            webView.scrollView.isScrollEnabled = false

            let observer = LoadObserver()
            webView.navigationDelegate = observer
            // Wrap the SVG in a tiny HTML shell so it scales to the WebView
            // viewport regardless of whether the source has explicit width/
            // height attributes — viewBox is enough.
            let html = """
                <!doctype html><html><head><meta charset="utf-8">
                <meta name="viewport" content="width=device-width,initial-scale=1.0">
                <style>html,body{margin:0;padding:0;background:transparent;}img{width:100vw;height:100vh;display:block;}</style>
                </head><body><img src="\(svgURL.lastPathComponent)"></body></html>
                """
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                var resumed = false
                observer.onFinish = {
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume()
                }
                webView.loadHTMLString(html, baseURL: svgURL.deletingLastPathComponent())
            }
            // One frame for the layout/paint to commit.
            try? await Task.sleep(nanoseconds: 50_000_000)

            let snapshotConfig = WKSnapshotConfiguration()
            snapshotConfig.rect = CGRect(origin: .zero, size: size)
            snapshotConfig.snapshotWidth = NSNumber(value: Double(pixelSize.width / scale))
            return try? await webView.takeSnapshot(configuration: snapshotConfig)
        }
    }
#endif
