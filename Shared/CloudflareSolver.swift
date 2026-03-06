import Foundation
import WebKit

@MainActor
class CloudflareSolver: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<[HTTPCookie], Error>?
    private var sessionKey: String = ""

    /// Loads claude.ai in a hidden WKWebView to solve the Cloudflare challenge
    /// and extract the clearance cookies needed for API requests.
    func solveChallengeAndGetCookies(sessionKey: String) async throws -> [HTTPCookie] {
        self.sessionKey = sessionKey

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()

            let webView = WKWebView(frame: .zero, configuration: config)
            webView.navigationDelegate = self
            self.webView = webView

            // Set the session key cookie before loading
            let cookie = HTTPCookie(properties: [
                .name: "sessionKey",
                .value: sessionKey,
                .domain: ".claude.ai",
                .path: "/",
                .secure: "TRUE",
            ])!

            webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
                let request = URLRequest(url: URL(string: "https://claude.ai/api/organizations")!)
                webView.load(request)
            }

            // Timeout after 15 seconds
            Task {
                try? await Task.sleep(for: .seconds(15))
                if self.continuation != nil {
                    self.continuation?.resume(throwing: UsageServiceError.networkError(
                        NSError(domain: "CloudflareSolver", code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Cloudflare challenge timed out"])
                    ))
                    self.continuation = nil
                    self.cleanup()
                }
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            // Give Cloudflare JS a moment to set cookies
            try? await Task.sleep(for: .seconds(2))
            let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            let cfCookies = cookies.filter { $0.domain.contains("claude.ai") }

            print("[DEBUG] Got \(cfCookies.count) cookies from WKWebView")
            for cookie in cfCookies {
                print("[DEBUG]   \(cookie.name) = \(cookie.value.prefix(20))...")
            }

            self.continuation?.resume(returning: cfCookies)
            self.continuation = nil
            self.cleanup()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.continuation?.resume(throwing: UsageServiceError.networkError(error))
            self.continuation = nil
            self.cleanup()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            // The navigation "fails" because the API returns JSON, not HTML the webview can render.
            // That's fine — the cookies should still be set. Extract them.
            let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            let cfCookies = cookies.filter { $0.domain.contains("claude.ai") }

            if cfCookies.count > 1 {
                // We have cookies beyond just our sessionKey — Cloudflare likely set clearance
                self.continuation?.resume(returning: cfCookies)
            } else {
                self.continuation?.resume(throwing: UsageServiceError.networkError(error))
            }
            self.continuation = nil
            self.cleanup()
        }
    }

    private func cleanup() {
        webView?.navigationDelegate = nil
        webView = nil
    }
}
