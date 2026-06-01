import SwiftUI
import WebKit

struct EncounterAuthenticatedWebView: View {
    let url: URL
    let cookiesData: Data
    var reloadID: UUID = UUID()
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?

    var body: some View {
        EncounterAuthenticatedWebViewRepresentable(
            url: url,
            cookiesData: cookiesData,
            reloadID: reloadID,
            isLoading: $isLoading,
            errorMessage: $errorMessage
        )
    }
}

private struct EncounterAuthenticatedWebViewRepresentable: UIViewRepresentable {
    let url: URL
    let cookiesData: Data
    let reloadID: UUID
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, errorMessage: $errorMessage)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.lastReloadID = reloadID
        context.coordinator.load(url: url, cookiesData: cookiesData)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastReloadID != reloadID else { return }
        context.coordinator.lastReloadID = reloadID
        context.coordinator.load(url: url, cookiesData: cookiesData)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        @Binding var isLoading: Bool
        @Binding var errorMessage: String?
        weak var webView: WKWebView?
        var lastReloadID: UUID?

        init(isLoading: Binding<Bool>, errorMessage: Binding<String?>) {
            _isLoading = isLoading
            _errorMessage = errorMessage
        }

        func load(url: URL, cookiesData: Data) {
            errorMessage = nil
            isLoading = true

            let cookies = EncounterCookieImporter.httpCookies(from: cookiesData, for: url)
            let store = webView?.configuration.websiteDataStore.httpCookieStore

            guard let store else {
                webView?.load(URLRequest(url: url))
                return
            }

            if cookies.isEmpty {
                webView?.load(URLRequest(url: url))
                return
            }

            let group = DispatchGroup()
            for cookie in cookies {
                group.enter()
                store.setCookie(cookie) { group.leave() }
            }
            group.notify(queue: .main) { [weak self] in
                self?.webView?.load(URLRequest(url: url))
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading = false
            errorMessage = error.localizedDescription
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return
            }
            isLoading = false
            errorMessage = error.localizedDescription
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}

enum EncounterCookieImporter {
    private struct ExportedCookie: Decodable {
        let name: String
        let value: String
        let path: String
        let domain: String
        let expires: String
        let secure: Bool
    }

    static func httpCookies(from data: Data, for pageURL: URL) -> [HTTPCookie] {
        guard let exported = try? JSONDecoder().decode([ExportedCookie].self, from: data) else {
            return []
        }

        return exported.compactMap { item in
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: item.name,
                .value: item.value,
                .path: item.path.isEmpty ? "/" : item.path,
                .domain: normalizedDomain(item.domain, pageHost: pageURL.host ?? ""),
            ]
            if item.secure {
                properties[.secure] = "TRUE"
            }
            if let expires = parseExpires(item.expires), expires.timeIntervalSinceNow > 0 {
                properties[.expires] = expires
            }
            return HTTPCookie(properties: properties)
        }
    }

    private static func normalizedDomain(_ domain: String, pageHost: String) -> String {
        if domain.isEmpty {
            return pageHost.hasPrefix(".") ? pageHost : ".\(pageHost)"
        }
        return domain
    }

    private static func parseExpires(_ value: String) -> Date? {
        if value.isEmpty || value.hasPrefix("0001-") {
            return nil
        }
        let formatters = [
            ISO8601DateFormatter(),
            {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return formatter
            }(),
        ]
        for formatter in formatters {
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }
}
