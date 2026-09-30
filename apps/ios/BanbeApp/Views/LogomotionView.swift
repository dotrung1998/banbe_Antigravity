import SwiftUI
import WebKit

/// Splash-only logo animation: the Adobe Animate/CreateJS "logomotion"
/// export, bundled offline under `public/logomotion` (see project.yml,
/// `../../public/logomotion` folder resource) and rendered via WKWebView on
/// a transparent canvas. Mirrors src/screens/Splash.jsx's own <iframe>
/// approach on web — the animation itself is authored once, in HTML/JS, and
/// both platforms just host it. `isUserInteractionEnabled = false` lets the
/// tap-to-dismiss gesture on SplashView's own ZStack fall through instead of
/// being swallowed by the web view, the same role `pointerEvents: 'none'`
/// plays on web's <iframe>.
struct LogomotionView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.backgroundColor = .clear
        webView.isUserInteractionEnabled = false
        if let folderURL = Bundle.main.url(forResource: "logomotion", withExtension: nil),
           let fileURL = Bundle.main.url(forResource: "logomotion2309", withExtension: "html", subdirectory: "logomotion") {
            webView.loadFileURL(fileURL, allowingReadAccessTo: folderURL)
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
