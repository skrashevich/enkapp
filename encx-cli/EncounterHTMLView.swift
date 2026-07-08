import SwiftUI
import WebKit

struct EncounterHTMLView: View {
    let html: String
    @State private var height: CGFloat = 80
    @State private var zoomImage: ZoomImageTarget?

    var body: some View {
        EncounterHTMLWebView(html: html, contentHeight: $height) { url in
            zoomImage = ZoomImageTarget(url: url)
        }
        .frame(height: max(height, 44))
        .fullScreenCover(item: $zoomImage) { target in
            ZoomableImageViewer(url: target.url) {
                zoomImage = nil
            }
        }
    }
}

struct ZoomImageTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct EncounterHTMLWebView: UIViewRepresentable {
    let html: String
    @Binding var contentHeight: CGFloat
    var onImageTap: (URL) -> Void

    private static let measureHeightJS = """
    (() => {
        const body = document.body;
        if (!body) { return 0; }

        const bodyTop = body.getBoundingClientRect().top;
        const computedBody = window.getComputedStyle(body);
        let bottom = 0;

        const range = document.createRange();
        range.selectNodeContents(body);
        const rangeRect = range.getBoundingClientRect();
        if (rangeRect.height > 0) {
            bottom = Math.max(bottom, rangeRect.bottom - bodyTop);
        }

        for (const element of body.querySelectorAll('*')) {
            const style = window.getComputedStyle(element);
            if (style.display === 'none' || style.visibility === 'hidden') { continue; }

            const rect = element.getBoundingClientRect();
            if (rect.width > 0 || rect.height > 0) {
                bottom = Math.max(bottom, rect.bottom - bodyTop);
            }
        }

        return Math.ceil(bottom + parseFloat(computedBody.paddingBottom || '0'));
    })()
    """

    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight, onImageTap: onImageTap)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "imageTapped")
        controller.addUserScript(
            WKUserScript(
                source: Self.imageTapJS,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator
        return webView
    }

    private static let imageTapJS = """
    (() => {
        function bind(img) {
            if (img.dataset.tapBound) { return; }
            img.dataset.tapBound = '1';
            img.style.cursor = 'zoom-in';
            img.addEventListener('click', () => {
                const src = img.currentSrc || img.src;
                if (src) {
                    window.webkit.messageHandlers.imageTapped.postMessage(src);
                }
            });
        }
        document.querySelectorAll('img').forEach(bind);
        new MutationObserver(mutations => {
            for (const m of mutations) {
                for (const node of m.addedNodes) {
                    if (node.tagName === 'IMG') { bind(node); }
                    else if (node.querySelectorAll) { node.querySelectorAll('img').forEach(bind); }
                }
            }
        }).observe(document.body, { childList: true, subtree: true });
    })()
    """

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        context.coordinator.resetHeight()
        webView.loadHTMLString(wrappedHTML(html), baseURL: nil)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "imageTapped")
    }

    private func wrappedHTML(_ body: String) -> String {
        let sanitizedBody = body.removingHTMLScriptAndStyleBlocks()
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          html, body {
            margin: 0;
            padding: 0;
            background: transparent;
            color: #fff;
            font: 15px/1.45 -apple-system, BlinkMacSystemFont, sans-serif;
            overflow: visible;
          }
          body { padding-bottom: 12px; box-sizing: border-box; }
          table { border-collapse: collapse; width: 100%; color: #fff; }
          td, th { border: 1px solid #444; padding: 6px 8px; vertical-align: middle; }
          img {
            max-width: 100%;
            max-height: 340px;
            height: auto;
            width: auto;
            object-fit: contain;
            display: block;
          }
          a { color: #5bc0de; }
          p { margin: 0 0 8px; }
          h1, h2, h3, h4 { margin: 0 0 10px; line-height: 1.25; }
        </style>
        </head>
        <body>\(sanitizedBody)</body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var contentHeight: CGFloat
        let onImageTap: (URL) -> Void
        var lastHTML = ""

        init(contentHeight: Binding<CGFloat>, onImageTap: @escaping (URL) -> Void) {
            _contentHeight = contentHeight
            self.onImageTap = onImageTap
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "imageTapped",
                  let src = message.body as? String,
                  let url = URL(string: src) else { return }
            onImageTap(url)
        }

        func resetHeight() {
            DispatchQueue.main.async {
                self.contentHeight = 80
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            measureHeight(in: webView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.measureHeight(in: webView)
            }
            webView.evaluateJavaScript(
                """
                Promise.all(Array.from(document.images).map(img =>
                    img.complete ? Promise.resolve() : new Promise(resolve => {
                        img.addEventListener('load', resolve, { once: true });
                        img.addEventListener('error', resolve, { once: true });
                    })
                ))
                """
            ) { _, _ in
                self.measureHeight(in: webView)
            }
        }

        private func measureHeight(in webView: WKWebView) {
            webView.evaluateJavaScript(EncounterHTMLWebView.measureHeightJS) { result, _ in
                let measured = Self.height(from: result)
                guard measured > 0 else { return }
                let padded = measured + 16
                DispatchQueue.main.async {
                    if abs(self.contentHeight - padded) > 0.5 {
                        self.contentHeight = padded
                    }
                }
            }
        }

        private static func height(from result: Any?) -> CGFloat {
            if let number = result as? NSNumber {
                return CGFloat(number.doubleValue)
            }
            if let value = result as? Double {
                return CGFloat(value)
            }
            if let value = result as? CGFloat {
                return value
            }
            return 0
        }
    }
}
