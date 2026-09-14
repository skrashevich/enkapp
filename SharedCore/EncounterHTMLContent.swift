import Foundation

nonisolated enum EncounterHTMLContent {
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
