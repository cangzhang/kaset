import XCTest
@testable import Kaset

/// Tests for HomeViewModel using mock client.
@MainActor
final class HomeViewModelTests: XCTestCase {
    private var mockClient: MockYTMusicClient!
    private var viewModel: HomeViewModel!

    override func setUp() async throws {
        mockClient = MockYTMusicClient()
        viewModel = HomeViewModel(client: mockClient)
    }

    override func tearDown() async throws {
        mockClient = nil
        viewModel = nil
    }

    func testInitialState() {
        XCTAssertEqual(viewModel.loadingState, .idle)
        XCTAssertTrue(viewModel.sections.isEmpty)
    }

    func testLoadSuccess() async {
        // Given
        let expectedSections = [
            TestFixtures.makeHomeSection(title: "Quick picks"),
            TestFixtures.makeHomeSection(title: "Recommended"),
        ]
        mockClient.homeResponse = HomeResponse(sections: expectedSections)

        // When
        await viewModel.load()

        // Then
        XCTAssertTrue(mockClient.getHomeCalled)
        XCTAssertEqual(viewModel.loadingState, .loaded)
        XCTAssertEqual(viewModel.sections.count, 2)
        XCTAssertEqual(viewModel.sections[0].title, "Quick picks")
        XCTAssertEqual(viewModel.sections[1].title, "Recommended")
    }

    func testLoadError() async {
        // Given
        mockClient.shouldThrowError = YTMusicError.networkError(underlying: URLError(.notConnectedToInternet))

        // When
        await viewModel.load()

        // Then
        XCTAssertTrue(mockClient.getHomeCalled)
        if case let .error(message) = viewModel.loadingState {
            XCTAssertFalse(message.isEmpty)
        } else {
            XCTFail("Expected error state")
        }
        XCTAssertTrue(viewModel.sections.isEmpty)
    }

    func testLoadDoesNotDuplicateWhenAlreadyLoading() async {
        // Given
        mockClient.homeResponse = TestFixtures.makeHomeResponse(sectionCount: 1)

        // When - load twice sequentially (since we're on MainActor)
        await viewModel.load()
        await viewModel.load()

        // Then - second load should be skipped when already loaded
        XCTAssertEqual(mockClient.getHomeCallCount, 2)
    }

    func testRefreshClearsSectionsAndReloads() async {
        // Given - load initial data
        mockClient.homeResponse = TestFixtures.makeHomeResponse(sectionCount: 2)
        await viewModel.load()
        XCTAssertEqual(viewModel.sections.count, 2)

        // When - refresh with new data
        mockClient.homeResponse = TestFixtures.makeHomeResponse(sectionCount: 3)
        await viewModel.refresh()

        // Then
        XCTAssertEqual(viewModel.sections.count, 3)
        XCTAssertEqual(mockClient.getHomeCallCount, 2)
    }
}
