import SwiftUI
import WebKit

/// The Cloudflare Turnstile widget for the sign-up form. Turnstile only renders on the site
/// key's hostnames, so the widget lives on a tiny page at square-off.com/turnstile shown in a
/// transparent web view; the page posts `{token}`, `{expired: true}` or `{error}` to the
/// `turnstile` message handler (hero-client `pages/turnstile.tsx`). A token is single use:
/// bump `reload` after a refused sign-up so the widget is solved again.
struct TurnstileView: UIViewRepresentable {
    let url: URL
    @Binding var token: String?
    @Binding var failed: Bool
    var reload = 0

    static let handlerName = "turnstile"

    func makeCoordinator() -> Coordinator { Coordinator(token: $token, failed: $failed) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: Self.handlerName)
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: url))
        context.coordinator.loadedGeneration = reload
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.token = $token
        context.coordinator.failed = $failed
        if context.coordinator.loadedGeneration != reload {
            context.coordinator.loadedGeneration = reload
            token = nil
            failed = false
            view.load(URLRequest(url: url))
        }
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: handlerName)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var token: Binding<String?>
        var failed: Binding<Bool>
        var loadedGeneration = 0

        init(token: Binding<String?>, failed: Binding<Bool>) {
            self.token = token
            self.failed = failed
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == TurnstileView.handlerName, let body = message.body as? [String: Any] else { return }
            if let value = body["token"] as? String, !value.isEmpty {
                token.wrappedValue = value
                failed.wrappedValue = false
            } else if body["expired"] != nil {
                token.wrappedValue = nil
            } else if body["error"] != nil {
                token.wrappedValue = nil
                failed.wrappedValue = true
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            failed.wrappedValue = true
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            failed.wrappedValue = true
        }

        /// The page must stay on square-off.com; anything it tries to open goes nowhere.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            action.targetFrame?.isMainFrame == false || action.navigationType == .other ? .allow : .cancel
        }
    }
}
