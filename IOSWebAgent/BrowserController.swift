import Foundation
import WebKit
import UIKit

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
        guard let url = URL(string: value), isAllowedWebURL(url) else { return }
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

    func waitForPageSettled() async throws {
        guard webView != nil else { throw AgentError.noWebView }
        try await Task.sleep(for: .milliseconds(180))

        var stableChecks = 0
        for _ in 0..<24 {
            try Task.checkCancellation()
            let loading = webView?.isLoading ?? false
            let readyState = (try? await evaluate("document.readyState")) as? String ?? ""

            if !loading && readyState != "loading" {
                stableChecks += 1
                if stableChecks >= 2 { return }
            } else {
                stableChecks = 0
            }
            try await Task.sleep(for: .milliseconds(250))
        }
    }

    func captureScreenshot() async -> BrowserScreenshot? {
        guard let webView else { return nil }

        return await withCheckedContinuation { continuation in
            webView.takeSnapshot(with: nil) { image, _ in
                guard let image,
                      let data = image.jpegData(compressionQuality: 0.55) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: BrowserScreenshot(
                    base64JPEG: data.base64EncodedString(),
                    width: image.size.width,
                    height: image.size.height
                ))
            }
        }
    }

    func snapshot() async throws -> PageSnapshot {
        guard webView != nil else { throw AgentError.noWebView }
        let script = #"""
        (() => {
          const isVisible = (el) => {
            const r = el.getBoundingClientRect();
            const s = getComputedStyle(el);
            return r.width > 0 && r.height > 0 && s.display !== 'none' && s.visibility !== 'hidden' && Number(s.opacity || 1) > 0;
          };
          const clean = (v, n = 180) => (v || '').replace(/\s+/g, ' ').trim().slice(0, n);
          const selector = 'a,button,input,textarea,select,[role="button"],[onclick],[contenteditable="true"]';
          const sensitivePattern = /(pass(word)?|passwd|pin|otp|one.?time|verification|security.?code|cvv|cvc|card.?number)/i;
          const isSensitive = (el) => {
            const tag = el.tagName.toLowerCase();
            const type = (el.getAttribute('type') || '').toLowerCase();
            const autocomplete = (el.getAttribute('autocomplete') || '').toLowerCase();
            const hints = [
              el.getAttribute('name'),
              el.id,
              el.getAttribute('aria-label'),
              el.getAttribute('placeholder')
            ].filter(Boolean).join(' ');
            return tag === 'input' && (
              ['password', 'hidden', 'file'].includes(type) ||
              ['current-password', 'new-password', 'one-time-code'].includes(autocomplete) ||
              sensitivePattern.test(hints)
            );
          };
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
            const sensitive = isSensitive(el);
            const form = el.closest('form');
            elements.push({
              id,
              tag: el.tagName.toLowerCase(),
              text: sensitive ? '' : clean(el.innerText || el.textContent || el.value || ''),
              ariaLabel: clean(el.getAttribute('aria-label') || '') || null,
              placeholder: clean(el.getAttribute('placeholder') || '') || null,
              type: clean(el.getAttribute('type') || '') || null,
              href: clean(el.href || '') || null,
              formAction: form ? clean(form.action || '') || null : null,
              formMethod: form ? clean(form.method || '') || null : null,
              disabled: Boolean(el.disabled || el.getAttribute('aria-disabled') === 'true'),
              sensitive,
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
              if (el.disabled || el.getAttribute('aria-disabled') === 'true') return 'disabled';
              el.scrollIntoView({block:'center', inline:'center'});
              el.focus();
              el.click();
              return 'ok';
            })();
            """
            try await requireOK(js, actionName: "タップ")

        case "input":
            guard let target = action.target else { throw AgentError.actionFailed("targetがありません") }
            let text = action.text ?? ""
            let js = """
            (() => {
              const el = document.querySelector('[data-ios-agent-id=' + \(jsString(target)) + ']');
              if (!el) return 'not_found';
              if (el.disabled || el.getAttribute('aria-disabled') === 'true') return 'disabled';
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
            try await requireOK(js, actionName: "入力")

        case "tap_point":
            guard let x = action.x, let y = action.y else {
                throw AgentError.actionFailed("座標がありません")
            }
            let js = """
            (() => {
              const x = \(x);
              const y = \(y);
              const el = document.elementFromPoint(x, y);
              if (!el) return 'not_found';
              const init = {bubbles:true, cancelable:true, view:window, clientX:x, clientY:y};
              try { el.dispatchEvent(new PointerEvent('pointerdown', init)); } catch (_) {}
              el.dispatchEvent(new MouseEvent('mousedown', init));
              try { el.dispatchEvent(new PointerEvent('pointerup', init)); } catch (_) {}
              el.dispatchEvent(new MouseEvent('mouseup', init));
              el.dispatchEvent(new MouseEvent('click', init));
              return 'ok';
            })();
            """
            try await requireOK(js, actionName: "座標タップ")

        case "scroll":
            let delta = action.delta ?? 650
            _ = try await evaluate("window.scrollBy({top: \(delta), behavior: 'smooth'}); 'ok';")

        case "navigate":
            guard let rawURL = action.url,
                  let destination = URL(string: rawURL),
                  isAllowedWebURL(destination) else {
                throw AgentError.actionFailed("http/https以外のURLには移動できません")
            }
            currentURL = destination.absoluteString
            webView?.load(URLRequest(url: destination))

        case "back":
            goBack()

        case "wait":
            try await Task.sleep(for: .seconds(1.2))

        case "done", "confirm":
            break

        default:
            throw AgentError.actionFailed("未対応アクション: \(action.type)")
        }
    }

    private func requireOK(_ script: String, actionName: String) async throws {
        let result = try await evaluate(script) as? String
        switch result {
        case "ok":
            return
        case "not_found":
            throw AgentError.actionFailed("\(actionName)対象がページ上に見つかりません")
        case "disabled":
            throw AgentError.actionFailed("\(actionName)対象は無効化されています")
        default:
            throw AgentError.actionFailed("\(actionName)結果を確認できません")
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

    private func isAllowedWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return false
        }
        return true
    }

    private func jsString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return encoded
    }
}
