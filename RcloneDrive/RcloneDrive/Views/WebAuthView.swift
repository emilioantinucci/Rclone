import SwiftUI
import WebKit

/// WKWebView-based OAuth view that intercepts the redirect to localhost:53682
struct WebAuthView: UIViewRepresentable {
    let url: URL
    let onAuthCode: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onAuthCode: onAuthCode)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        let onAuthCode: (URL) -> Void

        init(onAuthCode: @escaping (URL) -> Void) {
            self.onAuthCode = onAuthCode
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url,
               url.host == "localhost" && url.port == 53682 {
                decisionHandler(.cancel)
                onAuthCode(url)
                return
            }
            decisionHandler(.allow)
        }
    }
}
