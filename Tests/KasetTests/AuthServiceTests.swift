import XCTest
@testable import Kaset

/// Tests for AuthService.
@MainActor
final class AuthServiceTests: XCTestCase {
    var authService: AuthService!
    var mockWebKitManager: MockWebKitManager!

    override func setUp() async throws {
        mockWebKitManager = MockWebKitManager()
        authService = AuthService(webKitManager: mockWebKitManager)
    }

    override func tearDown() async throws {
        authService = nil
        mockWebKitManager = nil
    }

    func testInitialState() {
        XCTAssertEqual(authService.state, .initializing)
        XCTAssertFalse(authService.needsReauth)
    }

    func testIsInitializing() {
        XCTAssertTrue(authService.state.isInitializing)
        XCTAssertFalse(authService.state.isLoggedIn)

        authService.completeLogin(sapisid: "test")
        XCTAssertFalse(authService.state.isInitializing)
        XCTAssertTrue(authService.state.isLoggedIn)
    }

    func testStartLogin() {
        authService.startLogin()
        XCTAssertEqual(authService.state, .loggingIn)
    }

    func testCompleteLogin() {
        authService.completeLogin(sapisid: "test-sapisid")
        XCTAssertEqual(authService.state, .loggedIn(sapisid: "test-sapisid"))
        XCTAssertFalse(authService.needsReauth)
    }

    func testSessionExpired() {
        authService.completeLogin(sapisid: "test-sapisid")
        authService.sessionExpired()

        XCTAssertEqual(authService.state, .loggedOut)
        XCTAssertTrue(authService.needsReauth)
    }

    func testStateIsLoggedIn() {
        XCTAssertFalse(authService.state.isLoggedIn)

        authService.completeLogin(sapisid: "test")
        XCTAssertTrue(authService.state.isLoggedIn)
    }

    func testSignOut() async {
        authService.completeLogin(sapisid: "test-sapisid")
        authService.needsReauth = true

        await authService.signOut()

        XCTAssertEqual(authService.state, .loggedOut)
        XCTAssertFalse(authService.needsReauth)
        // Verify mock was called (not real WebKit/Keychain)
        XCTAssertTrue(mockWebKitManager.clearAllDataCalled)
    }

    func testStateEquatable() {
        let state1 = AuthService.State.loggedOut
        let state2 = AuthService.State.loggedOut
        XCTAssertEqual(state1, state2)

        let state3 = AuthService.State.loggedIn(sapisid: "test")
        let state4 = AuthService.State.loggedIn(sapisid: "test")
        XCTAssertEqual(state3, state4)

        let state5 = AuthService.State.loggedIn(sapisid: "different")
        XCTAssertNotEqual(state3, state5)
    }
}
