import Foundation
@testable import Kaset

/// A mock implementation of YTMusicClientProtocol for testing.
@MainActor
final class MockYTMusicClient: YTMusicClientProtocol {
    // MARK: - Response Stubs

    var homeResponse: HomeResponse = .init(sections: [])
    var exploreResponse: HomeResponse = .init(sections: [])
    var searchResponse: SearchResponse = .empty
    var libraryPlaylists: [Playlist] = []
    var playlistDetails: [String: PlaylistDetail] = [:]
    var artistDetails: [String: ArtistDetail] = [:]

    // MARK: - Call Tracking

    private(set) var getHomeCalled = false
    private(set) var getHomeCallCount = 0
    private(set) var getExploreCalled = false
    private(set) var getExploreCallCount = 0
    private(set) var searchCalled = false
    private(set) var searchQueries: [String] = []
    private(set) var getLibraryPlaylistsCalled = false
    private(set) var getPlaylistCalled = false
    private(set) var getPlaylistIds: [String] = []
    private(set) var getArtistCalled = false
    private(set) var getArtistIds: [String] = []
    private(set) var rateSongCalled = false
    private(set) var rateSongVideoIds: [String] = []
    private(set) var rateSongRatings: [LikeStatus] = []
    private(set) var editSongLibraryStatusCalled = false
    private(set) var editSongLibraryStatusTokens: [[String]] = []
    private(set) var subscribeToPlaylistCalled = false
    private(set) var subscribeToPlaylistIds: [String] = []
    private(set) var unsubscribeFromPlaylistCalled = false
    private(set) var unsubscribeFromPlaylistIds: [String] = []

    // MARK: - Error Simulation

    var shouldThrowError: Error?

    // MARK: - Protocol Implementation

    func getHome() async throws -> HomeResponse {
        getHomeCalled = true
        getHomeCallCount += 1
        if let error = shouldThrowError { throw error }
        return homeResponse
    }

    func getExplore() async throws -> HomeResponse {
        getExploreCalled = true
        getExploreCallCount += 1
        if let error = shouldThrowError { throw error }
        return exploreResponse
    }

    func search(query: String) async throws -> SearchResponse {
        searchCalled = true
        searchQueries.append(query)
        if let error = shouldThrowError { throw error }
        return searchResponse
    }

    func getLibraryPlaylists() async throws -> [Playlist] {
        getLibraryPlaylistsCalled = true
        if let error = shouldThrowError { throw error }
        return libraryPlaylists
    }

    func getPlaylist(id: String) async throws -> PlaylistDetail {
        getPlaylistCalled = true
        getPlaylistIds.append(id)
        if let error = shouldThrowError { throw error }
        guard let detail = playlistDetails[id] else {
            throw YTMusicError.parseError(message: "Playlist not found: \(id)")
        }
        return detail
    }

    func getArtist(id: String) async throws -> ArtistDetail {
        getArtistCalled = true
        getArtistIds.append(id)
        if let error = shouldThrowError { throw error }
        guard let detail = artistDetails[id] else {
            throw YTMusicError.parseError(message: "Artist not found: \(id)")
        }
        return detail
    }

    func rateSong(videoId: String, rating: LikeStatus) async throws {
        rateSongCalled = true
        rateSongVideoIds.append(videoId)
        rateSongRatings.append(rating)
        if let error = shouldThrowError { throw error }
    }

    func editSongLibraryStatus(feedbackTokens: [String]) async throws {
        editSongLibraryStatusCalled = true
        editSongLibraryStatusTokens.append(feedbackTokens)
        if let error = shouldThrowError { throw error }
    }

    func subscribeToPlaylist(playlistId: String) async throws {
        subscribeToPlaylistCalled = true
        subscribeToPlaylistIds.append(playlistId)
        if let error = shouldThrowError { throw error }
    }

    func unsubscribeFromPlaylist(playlistId: String) async throws {
        unsubscribeFromPlaylistCalled = true
        unsubscribeFromPlaylistIds.append(playlistId)
        if let error = shouldThrowError { throw error }
    }

    // MARK: - Helper Methods

    /// Resets all call tracking.
    func reset() {
        getHomeCalled = false
        getHomeCallCount = 0
        getExploreCalled = false
        getExploreCallCount = 0
        searchCalled = false
        searchQueries = []
        getLibraryPlaylistsCalled = false
        getPlaylistCalled = false
        getPlaylistIds = []
        getArtistCalled = false
        getArtistIds = []
        rateSongCalled = false
        rateSongVideoIds = []
        rateSongRatings = []
        editSongLibraryStatusCalled = false
        editSongLibraryStatusTokens = []
        subscribeToPlaylistCalled = false
        subscribeToPlaylistIds = []
        unsubscribeFromPlaylistCalled = false
        unsubscribeFromPlaylistIds = []
        shouldThrowError = nil
    }
}
