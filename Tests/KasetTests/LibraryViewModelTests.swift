import XCTest
@testable import Kaset

/// Tests for LibraryViewModel using mock client.
@MainActor
final class LibraryViewModelTests: XCTestCase {
    private var mockClient: MockYTMusicClient!
    private var viewModel: LibraryViewModel!

    override func setUp() async throws {
        mockClient = MockYTMusicClient()
        viewModel = LibraryViewModel(client: mockClient)
    }

    override func tearDown() async throws {
        mockClient = nil
        viewModel = nil
    }

    func testInitialState() {
        XCTAssertEqual(viewModel.loadingState, .idle)
        XCTAssertTrue(viewModel.playlists.isEmpty)
        XCTAssertNil(viewModel.selectedPlaylistDetail)
    }

    func testLoadSuccess() async {
        // Given
        mockClient.libraryPlaylists = [
            TestFixtures.makePlaylist(id: "VL1", title: "Playlist 1"),
            TestFixtures.makePlaylist(id: "VL2", title: "Playlist 2"),
        ]

        // When
        await viewModel.load()

        // Then
        XCTAssertTrue(mockClient.getLibraryPlaylistsCalled)
        XCTAssertEqual(viewModel.loadingState, .loaded)
        XCTAssertEqual(viewModel.playlists.count, 2)
        XCTAssertEqual(viewModel.playlists[0].title, "Playlist 1")
    }

    func testLoadError() async {
        // Given
        mockClient.shouldThrowError = YTMusicError.authExpired

        // When
        await viewModel.load()

        // Then
        XCTAssertTrue(mockClient.getLibraryPlaylistsCalled)
        if case .error = viewModel.loadingState {
            // Expected
        } else {
            XCTFail("Expected error state")
        }
        XCTAssertTrue(viewModel.playlists.isEmpty)
    }

    func testLoadPlaylistSuccess() async {
        // Given
        let playlist = TestFixtures.makePlaylist(id: "VL-test")
        let playlistDetail = TestFixtures.makePlaylistDetail(playlist: playlist, trackCount: 5)
        mockClient.playlistDetails["VL-test"] = playlistDetail

        // When
        await viewModel.loadPlaylist(id: "VL-test")

        // Then
        XCTAssertTrue(mockClient.getPlaylistCalled)
        XCTAssertEqual(mockClient.getPlaylistIds.first, "VL-test")
        XCTAssertEqual(viewModel.playlistDetailLoadingState, .loaded)
        XCTAssertNotNil(viewModel.selectedPlaylistDetail)
        XCTAssertEqual(viewModel.selectedPlaylistDetail?.tracks.count, 5)
    }

    func testClearSelectedPlaylist() async {
        // Given - load a playlist
        let playlist = TestFixtures.makePlaylist(id: "VL-test")
        mockClient.playlistDetails["VL-test"] = TestFixtures.makePlaylistDetail(playlist: playlist)
        await viewModel.loadPlaylist(id: "VL-test")
        XCTAssertNotNil(viewModel.selectedPlaylistDetail)

        // When
        viewModel.clearSelectedPlaylist()

        // Then
        XCTAssertNil(viewModel.selectedPlaylistDetail)
        XCTAssertEqual(viewModel.playlistDetailLoadingState, .idle)
    }

    func testRefreshClearsAndReloads() async {
        // Given - load initial data
        mockClient.libraryPlaylists = [TestFixtures.makePlaylist(id: "VL1")]
        await viewModel.load()
        XCTAssertEqual(viewModel.playlists.count, 1)

        // When - refresh with different data
        mockClient.libraryPlaylists = [
            TestFixtures.makePlaylist(id: "VL2"),
            TestFixtures.makePlaylist(id: "VL3"),
        ]
        await viewModel.refresh()

        // Then
        XCTAssertEqual(viewModel.playlists.count, 2)
    }
}
