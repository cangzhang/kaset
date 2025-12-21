import Foundation
@testable import Kaset

/// A mock implementation of WebKitManagerProtocol for testing.
/// Does not interact with real WebKit or Keychain.
@MainActor
final class MockWebKitManager: WebKitManagerProtocol {
    // MARK: - Response Stubs

    var allCookies: [HTTPCookie] = []
    var sapisidValue: String?

    // MARK: - Call Tracking

    private(set) var getAllCookiesCalled = false
    private(set) var getCookiesForDomainCalled = false
    private(set) var getCookiesForDomains: [String] = []
    private(set) var cookieHeaderCalled = false
    private(set) var getSAPISIDCalled = false
    private(set) var hasAuthCookiesCalled = false
    private(set) var clearAllDataCalled = false
    private(set) var forceBackupCookiesCalled = false
    private(set) var logAuthCookiesCalled = false

    // MARK: - Protocol Implementation

    func getAllCookies() async -> [HTTPCookie] {
        getAllCookiesCalled = true
        return allCookies
    }

    func getCookies(for domain: String) async -> [HTTPCookie] {
        getCookiesForDomainCalled = true
        getCookiesForDomains.append(domain)
        return allCookies.filter { cookie in
            domain.hasSuffix(cookie.domain) || cookie.domain.hasSuffix(domain)
        }
    }

    func cookieHeader(for domain: String) async -> String? {
        cookieHeaderCalled = true
        let cookies = await getCookies(for: domain)
        guard !cookies.isEmpty else { return nil }
        let headerFields = HTTPCookie.requestHeaderFields(with: cookies)
        return headerFields["Cookie"]
    }

    func getSAPISID() async -> String? {
        getSAPISIDCalled = true
        return sapisidValue
    }

    func hasAuthCookies() async -> Bool {
        hasAuthCookiesCalled = true
        return sapisidValue != nil
    }

    func clearAllData() async {
        clearAllDataCalled = true
        // Does NOT clear real data - this is a mock
        allCookies = []
        sapisidValue = nil
    }

    func forceBackupCookies() async {
        forceBackupCookiesCalled = true
        // Does NOT interact with real Keychain
    }

    func logAuthCookies() async {
        logAuthCookiesCalled = true
        // No-op in mock
    }

    // MARK: - Helper Methods

    /// Resets all call tracking.
    func reset() {
        getAllCookiesCalled = false
        getCookiesForDomainCalled = false
        getCookiesForDomains = []
        cookieHeaderCalled = false
        getSAPISIDCalled = false
        hasAuthCookiesCalled = false
        clearAllDataCalled = false
        forceBackupCookiesCalled = false
        logAuthCookiesCalled = false
        allCookies = []
        sapisidValue = nil
    }
}
