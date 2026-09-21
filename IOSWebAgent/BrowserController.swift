import Foundation
import WebKit

@MainActor
final class BrowserController: ObservableObject {
    @Published var currentURL: String = "https://www.google.com"
    @Published var pageTitle: String = ""
    @Published var isLoading = false

    private(set) weak var webView: WKWebView?

    func attach(_ webView: WKWebView) {
        self.webView = webView
    }

    func load(_ rawURL: String) {
        var value = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.contains("://") {
            value = "https://" + value
        }
        guard let url = URL(string: value) else { return }
        currentURL = url.absoluteString
        webView?.load(URLRequest(url: url))
    }

    func goBack() {
        if webView?.canGoBack == true {
            webView?.goBack()
        }
    }

    func reload() {
        webView?.reload()
    }

    func snapshot() async throws -> PageSnapshot {
        guard let webView else { throw AgentError.noWebView }
        let script = #"""
        (() => {
          const isVisible = (el) => {
            const r = el.getBoundingClientRect();
            const s = getComputedStyle(el);
            return r.width > 0 && r.height > 0 && s.display !== 'none' && s.visibility !== 'hidden' && Number(s.opacity || 1) > 0;
          };
          const clean = (v, n = 180) => (v || '').replace(/\s+/g, ' ').trim().slice(0, n);
          const selector = 'a,button,input,textarea,select,[role="button"],[onclick],[contenteditable="true"]';
          window.__iosAgentCounter = window.__iosAgentCounter || 1;
          const elements = [];
          for (const el of document.querySelectorAll(selector)) {
            if (!isVisible(el)) continue;
            let id = el.getAttribute('data-ios-agent-id');
            if (!id) {
              id = 'e' + (window.__iosAgentCounter++);
              el.setAttribute('data-ios-agent-id', id);
            }
            const r = el.getBoundingClientRect();
            elements.push({
              id,
              tag: el.tagName.toLowerCase(),
              text: clean(el.innerText || el.textContent || el.value || ''),
              ariaLabel: clean(el.getAttribute('aria-label') || '') || null,
              placeholder: clean(el.getAttribute('placeholder') || '') || null,
              type: clean(el.getAttribute('type') || '') || null,
              href: clean(el.href || '') || null,
              x: Math.round(r.x),
              y: Math.round(r.y),
              width: Math.round(r.width),
              height: Math.round(r.height)
            });
            if (elements.length >= 180) break;
          }
          return JSON.stringify({
            title: document.title || '',
            url: location.href,
            bodyText: clean(document.body ? document.body.innerText : '', 12000),
            viewportWidth: window.innerWidth,
            viewportHeight: window.innerHeight,
            elements
          });
        })();
        """#

        let value = try await evaluate(script)
        guard let json = value as? String,
              let data = json.data(using: .utf8) else {
            throw AgentError.invalidSnapshot
        }
        return try JSONDecoder().decode(PageSnapshot.self, from: data)
    }

    func execute(_ action: AgentAction) async throws {
        switch action.type {
        case "tap":
            guard let target = action.target else { throw AgentError.actionFailed("targetがありません") }
            let js = """
            (() => {
              const el = document.querySelector('[data-ios-agent-id=' + \(jsString(target)) + ']');
              if (!el) return 'not_found';
              el.scrollIntoView({block:'center', inline:'center'});
              el.focus();
              el.click();
              return 'ok';
            })();
            """
            _ = try await evaluate(js)

        case "input":
            guard let target = action.target else { throw AgentError.actionFailed("targetがありません") }
            let text = action.text ?? ""
            let js = """
            (() => {
              const el = document.querySelector('[data-ios-agent-id=' + \(jsString(target)) + ']');
              if (!el) return 'not_found';
              el.scrollIntoView({block:'center', inline:'center'});
              el.focus();
              const value = \(jsString(text));
              if (el.isContentEditable) {
                el.innerText = value;
              } else {
                const proto = Object.getPrototypeOf(el);
                const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
                if (setter) setter.call(el, value); else el.value = value;
              }
              el.dispatchEvent(new Event('input', {bubbles:true}));
              el.dispatchEvent(new Event('change', {bubbles:true}));
              return 'ok';
            })();
            """
            _ = try await evaluate(js)

        case "scroll":
            let delta = action.delta ?? 650
            _ = try await evaluate("window.scrollBy({top: \(delta), behavior: 'smooth'}); 'ok';")

        case "navigate":
            guard let url = action.url else { throw AgentError.actionFailed("URLがありません") }
            load(url)

        case "back":
            goBack()

        case "wait":
            try await Task.sleep(nanoseconds: 1_200_000_000)

        case "done", "confirm":
            break

        default:
            throw AgentError.actionFailed("未対応アクション: \(action.type)")
        }
    }

    private func evaluate(_ script: String) async throws -> Any? {
        guard let webView else { throw AgentError.noWebView }
        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value)
                }
            }
        }
    }

    private func jsString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return encoded
    }
}
