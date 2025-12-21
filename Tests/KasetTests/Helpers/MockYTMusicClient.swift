import Foundation
@testable import Kaset

/// A mock implementation of YTMusicClientProtocol for testing.
@MainActor
final class MockYTMusicClient: YTMusicClientProtocol {
    // MARK: - Response Stubs

    var homeResponse: HomeResponse = .init(sections: [])
    var homeContinuationSections: [[HomeSection]] = []
    var exploreResponse: HomeResponse = .init(sections: [])
    var exploreContinuationSections: [[HomeSection]] = []
    var searchResponse: SearchResponse = .empty
    var searchSuggestions: [SearchSuggestion] = []
    var libraryPlaylists: [Playlist] = []
    var likedSongs: [Song] = []
    var playlistDetails: [String: PlaylistDetail] = [:]
    var artistDetails: [String: ArtistDetail] = [:]
    var artistSongs: [String: [Song]] = [:]
    var lyricsResponses: [String: Lyrics] = [:]

    // MARK: - Continuation State

    private var _homeContinuationIndex = 0
    private var _exploreContinuationIndex = 0

    var hasMoreHomeSections: Bool {
        _homeContinuationIndex < homeContinuationSections.count
    }

    var hasMoreExploreSections: Bool {
        _exploreContinuationIndex < exploreContinuationSections.count
    }

    // MARK: - Call Tracking

    private(set) var getHomeCalled = false
    private(set) var getHomeCallCount = 0
    private(set) var getHomeContinuationCalled = false
    private(set) var getHomeContinuationCallCount = 0
    private(set) var getExploreCalled = false
    private(set) var getExploreCallCount = 0
    private(set) var getExploreContinuationCalled = false
    private(set) var getExploreContinuationCallCount = 0
    private(set) var searchCalled = false
    private(set) var searchQueries: [String] = []
    private(set) var getSearchSuggestionsCalled = false
    private(set) var getSearchSuggestionsQueries: [String] = []
    private(set) var getLibraryPlaylistsCalled = false
    private(set) var getLikedSongsCalled = false
    private(set) var getPlaylistCalled = false
    private(set) var getPlaylistIds: [String] = []
    private(set) var getArtistCalled = false
    private(set) var getArtistIds: [String] = []
    private(set) var getArtistSongsCalled = false
    private(set) var getArtistSongsBrowseIds: [String] = []
    private(set) var rateSongCalled = false
    private(set) var rateSongVideoIds: [String] = []
    private(set) var rateSongRatings: [LikeStatus] = []
    private(set) var editSongLibraryStatusCalled = false
    private(set) var editSongLibraryStatusTokens: [[String]] = []
    private(set) var subscribeToPlaylistCalled = false
    private(set) var subscribeToPlaylistIds: [String] = []
    private(set) var unsubscribeFromPlaylistCalled = false
    private(set) var unsubscribeFromPlaylistIds: [String] = []
    private(set) var subscribeToArtistCalled = false
    private(set) var subscribeToArtistIds: [String] = []
    private(set) var unsubscribeFromArtistCalled = false
    private(set) var unsubscribeFromArtistIds: [String] = []
    private(set) var getLyricsCalled = false
    private(set) var getLyricsVideoIds: [String] = []

    // MARK: - Error Simulation

    var shouldThrowError: Error?

    // MARK: - Protocol Implementation

    func getHome() async throws -> HomeResponse {
        getHomeCalled = true
        getHomeCallCount += 1
        _homeContinuationIndex = 0
        if let error = shouldThrowError { throw error }
        return homeResponse
    }

    func getHomeContinuation() async throws -> [HomeSection]? {
        getHomeContinuationCalled = true
        getHomeContinuationCallCount += 1
        if let error = shouldThrowError { throw error }
        guard _homeContinuationIndex < homeContinuationSections.count else {
            return nil
        }
        let sections = homeContinuationSections[_homeContinuationIndex]
        _homeContinuationIndex += 1
        return sections
    }

    func getExplore() async throws -> HomeResponse {
        getExploreCalled = true
        getExploreCallCount += 1
        _exploreContinuationIndex = 0
        if let error = shouldThrowError { throw error }
        return exploreResponse
    }

    func getExploreContinuation() async throws -> [HomeSection]? {
        getExploreContinuationCalled = true
        getExploreContinuationCallCount += 1
        if let error = shouldThrowError { throw error }
        guard _exploreContinuationIndex < exploreContinuationSections.count else {
            return nil
        }
        let sections = exploreContinuationSections[_exploreContinuationIndex]
        _exploreContinuationIndex += 1
        return sections
    }

    func search(query: String) async throws -> SearchResponse {
        searchCalled = true
        searchQueries.append(query)
        if let error = shouldThrowError { throw error }
        return searchResponse
    }

    func getSearchSuggestions(query: String) async throws -> [SearchSuggestion] {
        getSearchSuggestionsCalled = true
        getSearchSuggestionsQueries.append(query)
        if let error = shouldThrowError { throw error }
        return searchSuggestions
    }

    func getLibraryPlaylists() async throws -> [Playlist] {
        getLibraryPlaylistsCalled = true
        if let error = shouldThrowError { throw error }
        return libraryPlaylists
    }

    func getLikedSongs() async throws -> [Song] {
        getLikedSongsCalled = true
        if let error = shouldThrowError { throw error }
        return likedSongs
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

    func getArtistSongs(browseId: String, params _: String?) async throws -> [Song] {
        getArtistSongsCalled = true
        getArtistSongsBrowseIds.append(browseId)
        if let error = shouldThrowError { throw error }
        return artistSongs[browseId] ?? []
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

    func subscribeToArtist(channelId: String) async throws {
        subscribeToArtistCalled = true
        subscribeToArtistIds.append(channelId)
        if let error = shouldThrowError { throw error }
    }

    func unsubscribeFromArtist(channelId: String) async throws {
        unsubscribeFromArtistCalled = true
        unsubscribeFromArtistIds.append(channelId)
        if let error = shouldThrowError { throw error }
    }

    func getLyrics(videoId: String) async throws -> Lyrics {
        getLyricsCalled = true
        getLyricsVideoIds.append(videoId)
        if let error = shouldThrowError { throw error }
        return lyricsResponses[videoId] ?? .unavailable
    }

    func getSong(videoId: String) async throws -> Song {
        if let error = shouldThrowError { throw error }
        return Song(
            id: videoId,
            title: "Mock Song",
            artists: [Artist(id: "mock-artist", name: "Mock Artist")],
            videoId: videoId
        )
    }

    // MARK: - Helper Methods

    /// Resets all call tracking.
    func reset() {
        getHomeCalled = false
        getHomeCallCount = 0
        getHomeContinuationCalled = false
        getHomeContinuationCallCount = 0
        _homeContinuationIndex = 0
        getExploreCalled = false
        getExploreCallCount = 0
        getExploreContinuationCalled = false
        getExploreContinuationCallCount = 0
        _exploreContinuationIndex = 0
        searchCalled = false
        searchQueries = []
        getSearchSuggestionsCalled = false
        getSearchSuggestionsQueries = []
        getLibraryPlaylistsCalled = false
        getLikedSongsCalled = false
        getPlaylistCalled = false
        getPlaylistIds = []
        getArtistCalled = false
        getArtistIds = []
        getArtistSongsCalled = false
        getArtistSongsBrowseIds = []
        rateSongCalled = false
        rateSongVideoIds = []
        rateSongRatings = []
        editSongLibraryStatusCalled = false
        editSongLibraryStatusTokens = []
        subscribeToPlaylistCalled = false
        subscribeToPlaylistIds = []
        unsubscribeFromPlaylistCalled = false
        unsubscribeFromPlaylistIds = []
        subscribeToArtistCalled = false
        subscribeToArtistIds = []
        unsubscribeFromArtistCalled = false
        unsubscribeFromArtistIds = []
        getLyricsCalled = false
        getLyricsVideoIds = []
        shouldThrowError = nil
    }
}
