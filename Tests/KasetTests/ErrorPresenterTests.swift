import Foundation
import Testing
@testable import Kaset

// MARK: - ActionTracker

/// Helper class to track action calls in a thread-safe way.
private final class ActionTracker: @unchecked Sendable {
    var called = false
}

// MARK: - ErrorPresenterTests

/// Tests for the ErrorPresenter service.
@Suite("ErrorPresenter", .serialized, .tags(.service))
@MainActor
struct ErrorPresenterTests {
    var sut: ErrorPresenter

    init() {
        self.sut = ErrorPresenter.shared
        self.sut.dismiss()
    }

    // MARK: - Presentation Tests

    @Test("Present shows error")
    func presentShowsError() {
        let error = PresentableError(title: "Test", message: "Test message")

        self.sut.present(error)

        #expect(self.sut.isShowingError == true)
        #expect(self.sut.currentError?.title == "Test")
        #expect(self.sut.currentError?.message == "Test message")
    }

    @Test("Dismiss clears error")
    func dismissClearsError() {
        self.sut.present(PresentableError(title: "Test", message: "Test message"))

        self.sut.dismiss()

        #expect(self.sut.isShowingError == false)
        #expect(self.sut.currentError == nil)
    }

    // MARK: - YTMusicError Conversion

    @Test("Present notAuthenticated error")
    func presentNotAuthenticatedError() {
        self.sut.present(YTMusicError.notAuthenticated)
        #expect(self.sut.currentError?.title == "Not Signed In")
    }

    @Test("Present authExpired error")
    func presentAuthExpiredError() {
        self.sut.present(YTMusicError.authExpired)
        #expect(self.sut.currentError?.title == "Session Expired")
    }

    @Test("Present network error")
    func presentNetworkError() {
        let urlError = URLError(.notConnectedToInternet)
        self.sut.present(YTMusicError.networkError(underlying: urlError))
        #expect(self.sut.currentError?.title == "Connection Error")
    }

    @Test("Present API error")
    func presentAPIError() {
        self.sut.present(YTMusicError.apiError(message: "Server error", code: 500))
        #expect(self.sut.currentError?.title == "Server Error")
    }

    @Test("Present parse error")
    func presentParseError() {
        self.sut.present(YTMusicError.parseError(message: "Invalid JSON"))
        #expect(self.sut.currentError?.title == "Data Error")
    }

    @Test("Present unknown error")
    func presentUnknownError() {
        self.sut.present(YTMusicError.unknown(message: "Something went wrong"))
        #expect(self.sut.currentError?.title == "Error")
        #expect(self.sut.currentError?.message == "Something went wrong")
    }

    // MARK: - Retry Action Tests

    @Test("Retry invokes action and dismisses")
    func retryInvokesAction() async {
        let tracker = ActionTracker()
        let error = PresentableError(
            title: "Test",
            message: "Test",
            retryAction: { tracker.called = true }
        )
        self.sut.present(error)

        await self.sut.retry()

        #expect(tracker.called == true)
        #expect(self.sut.isShowingError == false)
    }

    @Test("Retry without action dismisses")
    func retryWithoutActionDismisses() async {
        let error = PresentableError(title: "Test", message: "Test", retryAction: nil)
        self.sut.present(error)

        await self.sut.retry()

        #expect(self.sut.isShowingError == false)
    }

    // MARK: - Dismiss Action Tests

    @Test("Dismiss invokes action")
    func dismissInvokesAction() {
        let tracker = ActionTracker()
        let error = PresentableError(
            title: "Test",
            message: "Test",
            dismissAction: { tracker.called = true }
        )
        self.sut.present(error)

        self.sut.dismiss()

        #expect(tracker.called == true)
    }

    // MARK: - Generic Error Conversion

    @Test("Present URLError")
    func presentURLError() {
        let urlError = URLError(.notConnectedToInternet) as Error
        self.sut.present(urlError)
        #expect(self.sut.currentError?.title == "Connection Error")
    }

    @Test("Present generic error")
    func presentGenericError() {
        struct CustomError: Error {}
        self.sut.present(CustomError())
        #expect(self.sut.currentError?.title == "Error")
    }
}
