import Foundation
import os
import WebKit

// MARK: - WebKitManager

/// Manages WebKit data store for persistent cookies and session management.
@MainActor
@Observable
final class WebKitManager: NSObject {
    /// Shared singleton instance.
    static let shared = WebKitManager()

    /// The persistent website data store used across all WebViews.
    let dataStore: WKWebsiteDataStore

    /// Timestamp of the last cookie change (for observation).
    private(set) var cookiesDidChange: Date = .distantPast

    /// The YouTube Music origin URL.
    static let origin = "https://music.youtube.com"

    /// Required cookie name for authentication.
    static let authCookieName = "__Secure-3PAPISID"

    /// Fallback cookie name (non-secure version).
    static let fallbackAuthCookieName = "SAPISID"

    /// Custom user agent to appear as Safari to avoid "browser not supported" errors.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private let logger = DiagnosticsLogger.webKit

    override private init() {
        // Use the default persistent data store
        // This is more reliable than custom identifiers as it:
        // 1. Is the standard WebKit approach
        // 2. Shares cookies with the system's standard location
        // 3. Doesn't get reset when WebKit detects issues
        dataStore = WKWebsiteDataStore.default()

        super.init()

        // Observe cookie changes
        dataStore.httpCookieStore.add(self)

        // Force cookie store to load by accessing it
        // This helps with lazy-loading issues on cold start
        Task {
            let cookies = await dataStore.httpCookieStore.allCookies()
            logger.info("WebKitManager initialized - loaded \(cookies.count) cookies from persistent store")
        }

        logger.info("WebKitManager initialized with persistent data store")
    }

    /// Creates a WebView configuration using the shared persistent data store.
    func createWebViewConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        // Enable AirPlay for streaming to Apple TV, HomePod, etc.
        configuration.allowsAirPlayForMediaPlayback = true

        return configuration
    }

    /// Retrieves all cookies from the HTTP cookie store.
    func getAllCookies() async -> [HTTPCookie] {
        await dataStore.httpCookieStore.allCookies()
    }

    /// Gets cookies for a specific domain.
    func getCookies(for domain: String) async -> [HTTPCookie] {
        let allCookies = await getAllCookies()
        return allCookies.filter { cookie in
            domain.hasSuffix(cookie.domain) || cookie.domain.hasSuffix(domain)
        }
    }

    /// Builds a Cookie header string for the given domain.
    func cookieHeader(for domain: String) async -> String? {
        let cookies = await getCookies(for: domain)
        guard !cookies.isEmpty else { return nil }

        let headerFields = HTTPCookie.requestHeaderFields(with: cookies)
        return headerFields["Cookie"]
    }

    /// Retrieves the SAPISID cookie value used for authentication.
    /// Checks both secure and non-secure cookie variants.
    func getSAPISID() async -> String? {
        let cookies = await getCookies(for: "youtube.com")
        let allCookies = await getAllCookies()
        logger.debug("Checking for SAPISID - total cookies: \(allCookies.count), youtube.com cookies: \(cookies.count)")

        // Try secure cookie first, then fallback to non-secure
        let secureCookie = cookies.first { $0.name == Self.authCookieName }
        let fallbackCookie = cookies.first { $0.name == Self.fallbackAuthCookieName }

        if let cookie = secureCookie ?? fallbackCookie {
            // Log cookie expiration for debugging session issues
            if let expiresDate = cookie.expiresDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                let expiresStr = formatter.string(from: expiresDate)
                let isExpired = expiresDate < Date()
                logger.debug("Found \(cookie.name) cookie, expires: \(expiresStr), expired: \(isExpired)")

                if isExpired {
                    logger.warning("Auth cookie has expired!")
                    return nil
                }
            } else if cookie.isSessionOnly {
                logger.debug("Found \(cookie.name) cookie (session-only, no expiration)")
            }
            return cookie.value
        }

        let cookieNames = cookies.map(\.name).joined(separator: ", ")
        logger.debug("No auth cookie found. Available cookies: \(cookieNames)")
        return nil
    }

    /// Checks if the required authentication cookies exist.
    func hasAuthCookies() async -> Bool {
        let sapisid = await getSAPISID()
        return sapisid != nil
    }

    /// Logs all authentication-related cookies for debugging.
    /// Call this when troubleshooting login persistence issues.
    func logAuthCookies() async {
        let cookies = await getCookies(for: "youtube.com")
        let authCookieNames = ["SAPISID", "__Secure-3PAPISID", "SID", "HSID", "SSID", "APISID", "__Secure-1PAPISID"]

        logger.info("=== Auth Cookie Diagnostic ===")
        logger.info("Total youtube.com cookies: \(cookies.count)")

        for name in authCookieNames {
            if let cookie = cookies.first(where: { $0.name == name }) {
                let expiry: String
                if let date = cookie.expiresDate {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .short
                    expiry = formatter.string(from: date)
                } else if cookie.isSessionOnly {
                    expiry = "session-only"
                } else {
                    expiry = "unknown"
                }
                logger.info("✓ \(name): expires \(expiry)")
            } else {
                logger.info("✗ \(name): not found")
            }
        }
        logger.info("==============================")
    }

    /// Clears all website data (cookies, cache, etc.).
    func clearAllData() async {
        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let dateFrom = Date.distantPast

        logger.info("Clearing all WebKit data")

        await dataStore.removeData(ofTypes: allTypes, modifiedSince: dateFrom)

        logger.info("WebKit data cleared successfully")
    }
}

// MARK: WKHTTPCookieStoreObserver

extension WebKitManager: WKHTTPCookieStoreObserver {
    nonisolated func cookiesDidChange(in _: WKHTTPCookieStore) {
        Task { @MainActor in
            self.cookiesDidChange = Date()
            logger.debug("Cookies changed at \(self.cookiesDidChange)")
        }
    }
}
