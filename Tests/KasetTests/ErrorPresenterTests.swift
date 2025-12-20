import XCTest
@testable import Kaset

/// Tests for the ErrorPresenter service.
@MainActor
final class ErrorPresenterTests: XCTestCase {
    var sut: ErrorPresenter!

    override func setUp() async throws {
        sut = ErrorPresenter.shared
        sut.dismiss()
    }

    override func tearDown() async throws {
        sut.dismiss()
        sut = nil
    }

    // MARK: - Presentation Tests

    func testPresentShowsError() {
        // Given
        let error = PresentableError(title: "Test", message: "Test message")

        // When
        sut.present(error)

        // Then
        XCTAssertTrue(sut.isShowingError)
        XCTAssertEqual(sut.currentError?.title, "Test")
        XCTAssertEqual(sut.currentError?.message, "Test message")
    }

    func testDismissClearsError() {
        // Given
        sut.present(PresentableError(title: "Test", message: "Test message"))

        // When
        sut.dismiss()

        // Then
        XCTAssertFalse(sut.isShowingError)
        XCTAssertNil(sut.currentError)
    }

    // MARK: - YTMusicError Conversion

    func testPresentNotAuthenticatedError() {
        // When
        sut.present(YTMusicError.notAuthenticated)

        // Then
        XCTAssertEqual(sut.currentError?.title, "Not Signed In")
    }

    func testPresentAuthExpiredError() {
        // When
        sut.present(YTMusicError.authExpired)

        // Then
        XCTAssertEqual(sut.currentError?.title, "Session Expired")
    }

    func testPresentNetworkError() {
        // Given
        let urlError = URLError(.notConnectedToInternet)

        // When
        sut.present(YTMusicError.networkError(underlying: urlError))

        // Then
        XCTAssertEqual(sut.currentError?.title, "Connection Error")
    }

    func testPresentAPIError() {
        // When
        sut.present(YTMusicError.apiError(message: "Server error", code: 500))

        // Then
        XCTAssertEqual(sut.currentError?.title, "Server Error")
    }

    func testPresentParseError() {
        // When
        sut.present(YTMusicError.parseError(message: "Invalid JSON"))

        // Then
        XCTAssertEqual(sut.currentError?.title, "Data Error")
    }

    func testPresentUnknownError() {
        // When
        sut.present(YTMusicError.unknown(message: "Something went wrong"))

        // Then
        XCTAssertEqual(sut.currentError?.title, "Error")
        XCTAssertEqual(sut.currentError?.message, "Something went wrong")
    }

    // MARK: - Retry Action Tests

    func testRetryInvokesAction() async {
        // Given
        let expectation = XCTestExpectation(description: "Retry action called")
        let error = PresentableError(
            title: "Test",
            message: "Test",
            retryAction: { expectation.fulfill() }
        )
        sut.present(error)

        // When
        await sut.retry()

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertFalse(sut.isShowingError)
    }

    func testRetryWithoutActionDismisses() async {
        // Given
        let error = PresentableError(title: "Test", message: "Test", retryAction: nil)
        sut.present(error)

        // When
        await sut.retry()

        // Then
        XCTAssertFalse(sut.isShowingError)
    }

    // MARK: - Dismiss Action Tests

    func testDismissInvokesAction() {
        // Given
        let expectation = XCTestExpectation(description: "Dismiss action called")
        let error = PresentableError(
            title: "Test",
            message: "Test",
            dismissAction: { expectation.fulfill() }
        )
        sut.present(error)

        // When
        sut.dismiss()

        // Then
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Generic Error Conversion

    func testPresentURLError() {
        // Given
        let urlError = URLError(.notConnectedToInternet) as Error

        // When
        sut.present(urlError)

        // Then
        XCTAssertEqual(sut.currentError?.title, "Connection Error")
    }

    func testPresentGenericError() {
        // Given
        struct CustomError: Error {}

        // When
        sut.present(CustomError())

        // Then
        XCTAssertEqual(sut.currentError?.title, "Error")
    }
}
