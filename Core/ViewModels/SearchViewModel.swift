import Foundation
import Observation
import os

/// View model for the Search view.
@MainActor
@Observable
final class SearchViewModel {
    /// Current loading state.
    private(set) var loadingState: LoadingState = .idle

    /// Current search query.
    var query: String = "" {
        didSet {
            searchTask?.cancel()
            suggestionsTask?.cancel()
            if query.isEmpty {
                results = .empty
                suggestions = []
                loadingState = .idle
                lastSearchedQuery = nil
            } else if query != lastSearchedQuery {
                // Clear results when query changes from what was searched
                results = .empty
                loadingState = .idle
            }
        }
    }

    /// Search results.
    private(set) var results: SearchResponse = .empty

    /// The query that produced the current results.
    private var lastSearchedQuery: String?

    /// Search suggestions for autocomplete.
    private(set) var suggestions: [SearchSuggestion] = []

    /// Whether suggestions should be shown.
    var showSuggestions: Bool {
        !query.isEmpty && !suggestions.isEmpty && results.isEmpty
    }

    /// Filter for result types.
    var selectedFilter: SearchFilter = .all

    /// Available filters.
    enum SearchFilter: String, CaseIterable, Identifiable, Sendable {
        case all = "All"
        case songs = "Songs"
        case albums = "Albums"
        case artists = "Artists"
        case playlists = "Playlists"

        var id: String { rawValue }
    }

    /// Filtered results based on selected filter.
    var filteredItems: [SearchResultItem] {
        switch selectedFilter {
        case .all:
            results.allItems
        case .songs:
            results.songs.map { .song($0) }
        case .albums:
            results.albums.map { .album($0) }
        case .artists:
            results.artists.map { .artist($0) }
        case .playlists:
            results.playlists.map { .playlist($0) }
        }
    }

    let client: any YTMusicClientProtocol
    private let logger = DiagnosticsLogger.api
    private var searchTask: Task<Void, Never>?
    private var suggestionsTask: Task<Void, Never>?

    init(client: any YTMusicClientProtocol) {
        self.client = client
    }

    /// Fetches search suggestions with debounce.
    func fetchSuggestions() {
        suggestionsTask?.cancel()

        guard !query.isEmpty else {
            suggestions = []
            return
        }

        suggestionsTask = Task {
            // Faster debounce for suggestions (150ms vs 300ms for search)
            try? await Task.sleep(for: .milliseconds(150))

            guard !Task.isCancelled else { return }

            await performFetchSuggestions()
        }
    }

    /// Performs the actual suggestions fetch.
    private func performFetchSuggestions() async {
        let currentQuery = query

        do {
            let fetchedSuggestions = try await client.getSearchSuggestions(query: currentQuery)
            // Only update if query hasn't changed
            if query == currentQuery {
                suggestions = fetchedSuggestions
            }
        } catch {
            if !Task.isCancelled {
                logger.debug("Failed to fetch suggestions: \(error.localizedDescription)")
                // Don't show error for suggestions - just silently fail
            }
        }
    }

    /// Selects a suggestion and triggers search.
    func selectSuggestion(_ suggestion: SearchSuggestion) {
        suggestionsTask?.cancel()
        suggestions = []
        query = suggestion.query
        search()
    }

    /// Clears suggestions without affecting search.
    func clearSuggestions() {
        suggestionsTask?.cancel()
        suggestions = []
    }

    /// Performs a search with debounce.
    func search() {
        searchTask?.cancel()
        suggestionsTask?.cancel()
        suggestions = []

        guard !query.isEmpty else {
            results = .empty
            loadingState = .idle
            return
        }

        searchTask = Task {
            // Debounce: wait a bit before searching
            try? await Task.sleep(for: .milliseconds(300))

            guard !Task.isCancelled else { return }

            await performSearch()
        }
    }

    /// Performs the actual search.
    private func performSearch() async {
        loadingState = .loading
        let currentQuery = query
        logger.info("Searching for: \(currentQuery)")

        do {
            let searchResults = try await client.search(query: currentQuery)
            results = searchResults
            lastSearchedQuery = currentQuery
            loadingState = .loaded
            logger.info("Search complete: \(searchResults.allItems.count) results")
        } catch {
            if !Task.isCancelled {
                logger.error("Search failed: \(error.localizedDescription)")
                loadingState = .error(error.localizedDescription)
            }
        }
    }

    /// Clears search results.
    func clear() {
        searchTask?.cancel()
        suggestionsTask?.cancel()
        query = ""
        results = .empty
        suggestions = []
        lastSearchedQuery = nil
        loadingState = .idle
    }
}
