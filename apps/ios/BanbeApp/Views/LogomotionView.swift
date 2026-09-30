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
///
/// Completion-gating fix (2026-09-30) — the html/js used to only ever
/// signal `"logomotion-ready"`, fired on ASSET LOAD (the CreateJS loader's
/// own "complete" event), not on the animation having actually finished
/// playing (see `public/logomotion/logomotion2309.html`'s own doc comment).
/// SplashView needs a real "one full cycle finished" signal to gate FaceID/
/// app entry on — added here via a `WKScriptMessageHandler` (mirrors
/// `DocumentWebView.Coordinator`'s existing `NSObject`-subclass-as-
/// coordinator pattern in `DocumentViews.swift`, just for message handling
/// instead of navigation), registered for the message name
/// `"logomotionBridge"`, matching the new
/// `window.webkit.messageHandlers.logomotionBridge.postMessage(...)` call
/// the html/js now makes the instant its timeline reaches its last frame.
struct LogomotionView: UIViewRepresentable {
    /// Called at most once, on the main actor, the first time the
    /// animation reports it has played through one full cycle (or
    /// immediately, if Reduce Motion is on and the html/js skipped
    /// straight to a static frame — see that file's own `prefersReducedMotion()`).
    var onComplete: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "logomotionBridge")
        let webView = WKWebView(frame: .zero, configuration: config)
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

    /// Removes the message handler on teardown — `WKUserContentController.add(_:name:)`
    /// retains its handler strongly, which would otherwise keep this
    /// `Coordinator` (and, through its closure, anything `onComplete` itself
    /// captures) alive past this view's own lifetime.
    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "logomotionBridge")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        private let onComplete: (() -> Void)?
        private var fired = false
        init(onComplete: (() -> Void)?) { self.onComplete = onComplete }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "logomotionBridge" else { return }
            guard let body = message.body as? [String: Any], body["type"] as? String == "logomotion-complete" else { return }
            guard !fired else { return }
            fired = true
            DispatchQueue.main.async { [onComplete] in onComplete?() }
        }
    }
}
