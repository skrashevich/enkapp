import SwiftUI
import WebKit

@main
final class EncounterRenderingTests: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var answers: [String] = []
    var checks: [String: Bool] = [:]
    var errors: [String] = []
    let bonusURL = "https://d1.endata.cx/data/games/80715/z1_903486.png"
    let hintURL = "https://d1.endata.cx/data/games/80715/z_paseka.jpg"

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let html = """
        <img id="bonus" src="\(bonusURL)"><img id="hint" src="\(hintURL)">
        <button id="single" onclick="$('#Answer').val('го46').parent('form').submit()"><span id="nested">Продолжить</span></button>
        <button id="double" onclick="$('#Answer').val(&quot;двойной ответ&quot;).parent('form').submit()">Продолжить</button>
        <button id="unsupported" onclick="window.authorExecuted = true">Unsupported</button>
        <div id="divButton" onclick="$('#Answer').val('дивный').parent('form').submit()"><b id="divLabel">Продолжить</b></div>
        <img id="bad" src="data:image/png;base64,broken" onerror="window.webkit.messageHandlers.answerSubmitted.postMessage('injected')">
        <a id="javascriptLink" href="javascript:window.webkit.messageHandlers.answerSubmitted.postMessage('injected-link')">Untrusted link</a>
        <script>window.authorExecuted = true;</script>
        """
        let root = UIHostingController(rootView: ScrollView {
            EncounterHTMLView(html: html, onSubmitAnswer: { [weak self] in self?.answers.append($0) })
        }.background(Color.black))
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = root
        window?.makeKeyAndVisible()
        Task { await run(root: root) }
        return true
    }

    func webView(in view: UIView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        return view.subviews.lazy.compactMap { self.webView(in: $0) }.first
    }

    func js(_ web: WKWebView, _ source: String) async throws -> Any? {
        try await web.evaluateJavaScript(source)
    }

    func pause() async { try? await Task.sleep(for: .milliseconds(200)) }

    func run(root: UIViewController) async {
        defer { save(root: root) }
        do {
            let help = Help(helpID: 46, number: 1, helpText: "<img src=\"\(hintURL)\">", isPenalty: false, penalty: 0, requestConfirm: false, penaltyHelpState: 0, remainSeconds: 0, penaltyMessage: nil)
            checks["pureImageHelpUnlocked"] = help.unlockedText == help.helpText
            func hint(_ text: String) -> Help {
                Help(helpID: 1, number: 1, helpText: text, isPenalty: false, penalty: 0, requestConfirm: false, penaltyHelpState: 0, remainSeconds: 0, penaltyMessage: nil)
            }
            checks["emptyHelpLocked"] = hint("").unlockedText == nil
            checks["scriptOnlyHelpLocked"] = hint("<script>let ignored = '<img src=x>';</script>").unlockedText == nil
            checks["styleOnlyHelpLocked"] = hint("<style>body { color: red; }</style>").unlockedText == nil
            checks["placeholderHelpLocked"] = hint("Подсказка откроется через 10 минут").unlockedText == nil
            let scriptOnlyBonus = "Формат ответа: Фамилия\r\n<script>points.push({coords: [57.6, 39.8]});</script>"
            checks["scriptOnlyBonusIsPlainText"] = !EncounterHTMLContent.containsMarkup(scriptOnlyBonus)
            let imageBonus = "<img src=\"\(bonusURL)\">\r\nНазовите либо то, что в задании.\r\nФормат ответа: два слова\r\n<script>points.push({number: 9});</script>"
            checks["bonusKeepsAuthorLineBreaks"] = EncounterHTMLContent.containsMarkup(imageBonus)
                && EncounterHTMLContent.renderableBody(imageBonus)
                == "<img src=\"\(bonusURL)\"><br>Назовите либо то, что в задании.<br>Формат ответа: два слова"
            checks["explicitBreaksAreNotDoubled"] = EncounterHTMLContent.renderableBody("Первая<br/>\r\nВторая\r\n") == "Первая<br>Вторая"
            var web: WKWebView?
            for _ in 0..<100 {
                web = webView(in: root.view)
                if web != nil { break }
                await pause()
            }
            guard let web else { errors.append("WKWebView not mounted"); return }
            for _ in 0..<225 {
                let loaded = try? await js(web, "['bonus', 'hint'].every(id => { const i = document.getElementById(id); return i && i.complete && i.naturalWidth > 0; })") as? Bool
                if loaded == true { break }
                await pause()
            }
            checks["bonusImageLoaded"] = try await js(web, "document.getElementById('bonus').naturalWidth > 0") as? Bool == true
            checks["hintImageLoaded"] = try await js(web, "document.getElementById('hint').naturalWidth > 0") as? Bool == true
            checks["authorScriptRemoved"] = try await js(web, "window.authorExecuted === undefined && document.querySelectorAll('script').length === 0") as? Bool == true
            _ = try await js(web, "document.getElementById('unsupported').click()")
            checks["unsupportedOnclickRemoved"] = try await js(web, "window.authorExecuted === undefined && !document.getElementById('unsupported').hasAttribute('onclick')") as? Bool == true
            checks["authorOnerrorBlocked"] = answers.isEmpty
            let prevented = try await js(web, "!document.getElementById('nested').dispatchEvent(new MouseEvent('click', {bubbles:true, cancelable:true}))") as? Bool
            for _ in 0..<10 { await pause() }
            checks["singleNestedClickExactlyOnce"] = answers == ["го46"]
            checks["answerDefaultPrevented"] = prevented == true
            _ = try await js(web, "document.getElementById('double').click()")
            for _ in 0..<10 { await pause() }
            checks["doubleQuotedAnswerExactlyOnce"] = answers == ["го46", "двойной ответ"]
            _ = try await js(web, "document.getElementById('javascriptLink').click()")
            for _ in 0..<10 { await pause() }
            checks["authorJavascriptURLBlocked"] = answers == ["го46", "двойной ответ"]
            _ = try await js(web, "document.getElementById('divLabel').click()")
            for _ in 0..<10 { await pause() }
            checks["nonButtonClickSubmitsExactlyOnce"] = answers == ["го46", "двойной ответ", "дивный"]
            capture(name: "web-rendering.png")
            _ = try await js(web, "document.getElementById('bonus').click()")
            for _ in 0..<25 {
                if root.presentedViewController != nil { break }
                await pause()
            }
            checks["imageClickPresentsNativeCover"] = root.presentedViewController != nil
        } catch { errors.append(String(describing: error)) }
    }

    func save(root: UIViewController) {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        capture(name: "rendering.png")
        let result: [String: Any] = ["checks": checks, "errors": errors, "answers": answers, "passed": errors.isEmpty && checks.count == 19 && checks.values.allSatisfy { $0 }]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("results.json"))
        }
    }

    func capture(name: String) {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let window {
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            try? image.pngData()?.write(to: directory.appendingPathComponent(name))
        }
    }
}
