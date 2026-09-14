import Foundation

nonisolated enum EncounterHTMLContent {
    /// Whether anything is left for the web view to render once the blocks it drops are gone.
    /// Bodies that carry only an author `<script>` (bonus map pins, for instance) are plain text.
    static func containsMarkup(_ text: String) -> Bool {
        text.removingHTMLScriptAndStyleBlocks().contains("<")
    }

    /// The engine separates bonus and message lines with bare newlines, which HTML collapses into
    /// spaces. Restore them as `<br>` without doubling the breaks the author already wrote.
    static func renderableBody(_ text: String) -> String {
        var body = text.removingHTMLScriptAndStyleBlocks()
        body = body.replacingOccurrences(of: "\r\n", with: "\n")
        body = body.replacingOccurrences(of: "\r", with: "\n")
        body = body.replacingOccurrences(
            of: #"(?i)[ \t\n]*<br\s*/?>[ \t\n]*"#, with: "<br>", options: .regularExpression
        )
        body = body.replacingOccurrences(of: "\n", with: "<br>")
        return body.replacingOccurrences(
            of: #"(?i)^(?:\s|<br\s*/?>)+|(?:\s|<br\s*/?>)+$"#, with: "", options: .regularExpression
        )
    }

    /// Recognize the engine's literal answer buttons without loading jQuery or running author scripts.
    static let answerBridgeJS = #"""
    (() => {
        const pattern = /^\s*\$\(\s*(['"])#Answer\1\s*\)\s*\.val\(\s*("[^"\\]*"|'[^'\\]*')\s*\)\s*\.parent\(\s*(['"])form\3\s*\)\s*\.submit\(\s*\)\s*;?\s*$/;
        const answers = new WeakMap();
        for (const element of document.querySelectorAll('[onclick]')) {
            const match = (element.getAttribute('onclick') || '').match(pattern);
            element.removeAttribute('onclick');
            if (match) {
                answers.set(element, match[2].slice(1, -1));
                if (element.tagName === 'BUTTON') { element.type = 'button'; }
            }
        }
        document.addEventListener('click', event => {
            // The clickable element is not always a button: walk up from whatever was hit.
            let element = event.target;
            while (element && !answers.has(element)) { element = element.parentElement; }
            if (!element) { return; }
            event.preventDefault();
            event.stopImmediatePropagation();
            window.webkit.messageHandlers.answerSubmitted.postMessage(answers.get(element));
        }, true);
    })()
    """#
}
