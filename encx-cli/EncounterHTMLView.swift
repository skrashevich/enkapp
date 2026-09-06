import SwiftUI
import WebKit

struct EncounterHTMLView: View {
    let html: String
    /// Body type for the rendered document. SwiftUI's `.font()` cannot reach the web view, so the
    /// caller passes the size the surrounding design calls for (level task 19/1.38, hints 16/1.4).
    var fontSize: CGFloat = 15
    var lineHeight: CGFloat = 1.45
    @State private var height: CGFloat = 80
    @State private var zoomImage: ZoomImageTarget?

    var body: some View {
        EncounterHTMLWebView(
            html: html,
            fontSize: fontSize,
            lineHeight: lineHeight,
            contentHeight: $height
        ) { url in
            zoomImage = ZoomImageTarget(url: url)
        }
        .frame(height: max(height, 44))
        .fullScreenCover(item: $zoomImage) { target in
            ZoomableImageViewer(url: target.url, fileName: target.fileName) {
                zoomImage = nil
            }
        }
    }
}

struct ZoomImageTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }

    var fileName: String {
        let encodedName = url.lastPathComponent
        guard !encodedName.isEmpty else { return "Изображение" }
        return encodedName.removingPercentEncoding ?? encodedName
    }
}

private struct EncounterHTMLWebView: UIViewRepresentable {
    let html: String
    let fontSize: CGFloat
    let lineHeight: CGFloat
    @Binding var contentHeight: CGFloat
    var onImageTap: (URL) -> Void

    /// Expression yielding the content height, or 0 while the document has no usable layout width
    /// (a zero-width layout wraps every word and reports a wildly inflated height).
    private static let measureHeightJS = """
    (() => {
        const body = document.body;
        if (!body || body.clientWidth <= 0) { return 0; }

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
            if (style.position === 'fixed') { continue; }

            const rect = element.getBoundingClientRect();
            if (rect.width > 0 || rect.height > 0) {
                bottom = Math.max(bottom, rect.bottom - bodyTop);
            }
        }

        return Math.ceil(bottom + parseFloat(computedBody.paddingBottom || '0'));
    })()
    """

    /// Keeps the native frame in sync with the document: a one-shot measurement after `didFinish`
    /// goes stale as soon as the layout width changes (rotation, late SwiftUI sizing) or images and
    /// web fonts land, which is what leaves the block either inner-scrolling or padded with blank space.
    private static let heightReportJS = """
    (() => {
        let lastReported = -1;
        let scheduled = false;

        function report() {
            scheduled = false;
            const height = \(measureHeightJS);
            if (height <= 0 || Math.abs(height - lastReported) < 0.5) { return; }
            lastReported = height;
            window.webkit.messageHandlers.contentHeight.postMessage(height);
        }

        function schedule() {
            if (scheduled) { return; }
            scheduled = true;
            requestAnimationFrame(report);
            // rAF is throttled while the web view is off-screen; the timer guarantees a report.
            setTimeout(report, 250);
        }

        new ResizeObserver(schedule).observe(document.body);
        new MutationObserver(schedule).observe(document.body, {
            childList: true,
            subtree: true,
            characterData: true,
            attributes: true
        });
        window.addEventListener('resize', schedule);
        document.addEventListener('load', schedule, true);
        document.addEventListener('error', schedule, true);
        if (document.fonts && document.fonts.ready) {
            document.fonts.ready.then(schedule);
        }
        schedule();
    })()
    """

    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight, onImageTap: onImageTap)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "imageTapped")
        controller.add(context.coordinator, name: "imageContextRequested")
        controller.add(context.coordinator, name: "contentHeight")
        controller.addUserScript(
            WKUserScript(
                source: Self.heightReportJS,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        controller.addUserScript(
            WKUserScript(
                source: Self.imageTapJS,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        controller.addUserScript(
            WKUserScript(
                source: Self.coordinateLinkJS,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        // The block is sized to its content and lives inside the screen's own ScrollView, so the web
        // view must never scroll on its own — an inner scroll here hides part of the task text.
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.alwaysBounceVertical = false
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
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

        function reportContextTarget(target) {
            const img = target && target.closest ? target.closest('img') : null;
            const src = img ? (img.currentSrc || img.src || '') : '';
            window.webkit.messageHandlers.imageContextRequested.postMessage(src);
        }

        document.addEventListener('touchstart', event => {
            reportContextTarget(event.target);
        }, { capture: true, passive: true });
        document.addEventListener('contextmenu', event => {
            reportContextTarget(event.target);
        }, { capture: true });

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

    private static let coordinateLinkJS = """
    (() => {
        const patterns = [
            {
                regex: /(^|[^\\d.,])([+-]?\\d{1,2}\\.\\d+)\\s*(?:[,;]|\\s+)\\s*([+-]?\\d{1,3}\\.\\d+)(?![\\d.,])/g,
                parse: value => Number(value)
            },
            {
                regex: /(^|[^\\d.,])([+-]?\\d{1,2},\\d+)\\s*(?:;|\\s+)\\s*([+-]?\\d{1,3},\\d+)(?![\\d.,])/g,
                parse: value => Number(value.replace(',', '.'))
            }
        ];

        function eligibleTextNodes() {
            const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
            const nodes = [];
            let node;
            while ((node = walker.nextNode())) {
                const parent = node.parentElement;
                if (!parent || parent.closest('a, script, style, textarea, code')) { continue; }
                nodes.push(node);
            }
            return nodes;
        }

        function linkify(pattern) {
            for (const node of eligibleTextNodes()) {
                const text = node.nodeValue || '';
                pattern.regex.lastIndex = 0;
                let match;
                let cursor = 0;
                let changed = false;
                const fragment = document.createDocumentFragment();

                while ((match = pattern.regex.exec(text)) !== null) {
                    const prefix = match[1] || '';
                    const latitude = pattern.parse(match[2]);
                    const longitude = pattern.parse(match[3]);
                    if (Math.abs(latitude) > 90 || Math.abs(longitude) > 180) { continue; }

                    const coordinateStart = match.index + prefix.length;
                    const coordinateEnd = match.index + match[0].length;
                    fragment.append(document.createTextNode(text.slice(cursor, coordinateStart)));

                    const link = document.createElement('a');
                    link.href = `yandexmaps://maps.yandex.ru/?ll=${longitude},${latitude}&pt=${longitude},${latitude}&z=16`;
                    link.textContent = text.slice(coordinateStart, coordinateEnd);
                    link.title = 'Открыть координаты в Яндекс Картах';
                    fragment.append(link);

                    cursor = coordinateEnd;
                    changed = true;
                }

                if (changed) {
                    fragment.append(document.createTextNode(text.slice(cursor)));
                    node.replaceWith(fragment);
                }
            }
        }

        patterns.forEach(linkify);
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
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "imageContextRequested")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "contentHeight")
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
            font: \(fontSize)px/\(lineHeight) -apple-system, BlinkMacSystemFont, sans-serif;
            overflow: visible;
          }
          body {
            box-sizing: border-box;
            overflow-wrap: anywhere;
            word-break: break-word;
          }
          table { border-collapse: collapse; width: 100%; color: #fff; table-layout: fixed; }
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

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        @Binding var contentHeight: CGFloat
        let onImageTap: (URL) -> Void
        var lastHTML = ""
        private var contextImageURL: URL?

        init(contentHeight: Binding<CGFloat>, onImageTap: @escaping (URL) -> Void) {
            _contentHeight = contentHeight
            self.onImageTap = onImageTap
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "contentHeight" {
                applyHeight(Self.height(from: message.body))
                return
            }

            guard let src = message.body as? String else { return }

            switch message.name {
            case "imageTapped":
                guard let url = URL(string: src) else { return }
                onImageTap(url)
            case "imageContextRequested":
                contextImageURL = URL(string: src)
            default:
                break
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url,
                  CoordinateLinkifier.isYandexMapsURL(url) else {
                decisionHandler(.allow)
                return
            }

            CoordinateLinkifier.openYandexMaps(url)
            decisionHandler(.cancel)
        }

        func webView(
            _ webView: WKWebView,
            contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
            completionHandler: @escaping (UIContextMenuConfiguration?) -> Void
        ) {
            let imageURL = contextImageURL
            guard imageURL != nil || elementInfo.linkURL != nil else {
                completionHandler(nil)
                return
            }

            let configuration = UIContextMenuConfiguration(
                identifier: (imageURL ?? elementInfo.linkURL).map { $0.absoluteString as NSString },
                previewProvider: nil
            ) { suggestedActions in
                guard let imageURL,
                      let searchURL = Self.yandexImageSearchURL(for: imageURL) else {
                    return UIMenu(children: suggestedActions)
                }

                let searchAction = UIAction(
                    title: "Найти это изображение в Яндексе",
                    image: UIImage(systemName: "magnifyingglass")
                ) { _ in
                    UIApplication.shared.open(searchURL)
                }
                return UIMenu(children: [searchAction] + suggestedActions)
            }
            completionHandler(configuration)
        }

        func webView(
            _ webView: WKWebView,
            contextMenuDidEndForElement elementInfo: WKContextMenuElementInfo
        ) {
            contextImageURL = nil
        }

        private static func yandexImageSearchURL(for imageURL: URL) -> URL? {
            guard imageURL.scheme == "http" || imageURL.scheme == "https" else { return nil }

            var components = URLComponents(string: "https://yandex.ru/images/search")
            components?.queryItems = [
                URLQueryItem(name: "rpt", value: "imageview"),
                URLQueryItem(name: "url", value: imageURL.absoluteString)
            ]
            return components?.url
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
                self.applyHeight(Self.height(from: result))
            }
        }

        /// `measured` is the exact content bottom; the extra point absorbs fractional rounding so the
        /// last line never gets clipped, without leaving a visible gap before the next section.
        private func applyHeight(_ measured: CGFloat) {
            guard measured > 0 else { return }
            let target = measured + 1
            DispatchQueue.main.async {
                if abs(self.contentHeight - target) > 0.5 {
                    self.contentHeight = target
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
