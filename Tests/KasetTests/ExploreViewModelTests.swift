import XCTest
@testable import Kaset

/// Tests for ExploreViewModel using mock client.
@MainActor
final class ExploreViewModelTests: XCTestCase {
    private var mockClient: MockYTMusicClient!
    private var viewModel: ExploreViewModel!

    override func setUp() async throws {
        mockClient = MockYTMusicClient()
        viewModel = ExploreViewModel(client: mockClient)
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
            TestFixtures.makeHomeSection(title: "New releases"),
            TestFixtures.makeHomeSection(title: "Charts"),
            TestFixtures.makeHomeSection(title: "Moods & genres"),
        ]
        mockClient.exploreResponse = HomeResponse(sections: expectedSections)

        // When
        await viewModel.load()

        // Then
        XCTAssertTrue(mockClient.getExploreCalled)
        XCTAssertEqual(viewModel.loadingState, .loaded)
        XCTAssertEqual(viewModel.sections.count, 3)
        XCTAssertEqual(viewModel.sections[0].title, "New releases")
    }

    func testLoadError() async {
        // Given
        mockClient.shouldThrowError = YTMusicError.networkError(underlying: URLError(.timedOut))

        // When
        await viewModel.load()

        // Then
        XCTAssertTrue(mockClient.getExploreCalled)
        if case .error = viewModel.loadingState {
            // Expected
        } else {
            XCTFail("Expected error state")
        }
        XCTAssertTrue(viewModel.sections.isEmpty)
    }

    func testLoadDoesNotDuplicateWhenAlreadyLoading() async {
        // Given
        mockClient.exploreResponse = TestFixtures.makeHomeResponse(sectionCount: 1)

        // When - load twice sequentially (since we're on MainActor)
        await viewModel.load()
        await viewModel.load()

        // Then - second load should be called since state is loaded
        XCTAssertEqual(mockClient.getExploreCallCount, 2)
    }

    func testRefreshClearsSectionsAndReloads() async {
        // Given
        mockClient.exploreResponse = TestFixtures.makeHomeResponse(sectionCount: 2)
        await viewModel.load()
        XCTAssertEqual(viewModel.sections.count, 2)

        // When
        mockClient.exploreResponse = TestFixtures.makeHomeResponse(sectionCount: 4)
        await viewModel.refresh()

        // Then
        XCTAssertEqual(viewModel.sections.count, 4)
        XCTAssertEqual(mockClient.getExploreCallCount, 2)
    }
}
