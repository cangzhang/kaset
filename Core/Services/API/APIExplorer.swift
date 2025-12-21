import Foundation

// MARK: - API Explorer Tool

/// A development utility for exploring and documenting YouTube Music API endpoints.
///
/// ## Purpose
/// This tool enables discovery and testing of YouTube Music API endpoints to identify
/// new functionality that can be implemented in the app. It provides structured exploration
/// of both browse endpoints (content pages) and action endpoints (API operations).
///
/// ## Usage
/// ```swift
/// // In a test or debug context:
/// let explorer = APIExplorer(webKitManager: .shared)
///
/// // Explore a specific browse endpoint
/// let result = await explorer.exploreBrowseEndpoint("FEmusic_charts")
/// DiagnosticsLogger.api.info("\(result.summary)")
///
/// // Explore an action endpoint
/// let actionResult = await explorer.exploreActionEndpoint("player", body: ["videoId": "dQw4w9WgXcQ"])
/// DiagnosticsLogger.api.info("\(actionResult.responseKeys)")
/// ```
///
/// ## Security Note
/// This class is intended for development/debugging only. It logs response structures
/// but not sensitive user data. Do not use in production builds.
///
/// ## Documentation
/// Results from exploration should be documented in `docs/api-discovery.md`.
/// When new endpoints are implemented, update the documentation status accordingly.
@MainActor
final class APIExplorer {
    // MARK: - Types

    /// Result of exploring a browse endpoint.
    struct BrowseResult: Sendable {
        /// The browse ID that was explored (e.g., "FEmusic_charts")
        let browseId: String

        /// Whether the request succeeded
        let success: Bool

        /// HTTP status code if available
        let statusCode: Int?

        /// Error message if the request failed
        let errorMessage: String?

        /// Top-level keys in the response JSON
        let responseKeys: [String]

        /// Number of sections found (if applicable)
        let sectionCount: Int

        /// Types of sections found (e.g., ["musicCarouselShelfRenderer", "gridRenderer"])
        let sectionTypes: [String]

        /// Whether authentication appears to be required
        let requiresAuth: Bool

        /// A human-readable summary of the exploration result
        var summary: String {
            if !self.success {
                let authNote = self.requiresAuth ? " (requires authentication)" : ""
                return "❌ \(self.browseId): \(self.errorMessage ?? "Unknown error")\(authNote)"
            }
            let sectionInfo = self.sectionCount > 0 ? ", \(self.sectionCount) sections" : ""
            let typesInfo = self.sectionTypes.isEmpty ? "" : " [\(self.sectionTypes.joined(separator: ", "))]"
            return "✅ \(self.browseId): \(self.responseKeys.count) keys\(sectionInfo)\(typesInfo)"
        }
    }

    /// Result of exploring an action endpoint.
    struct ActionResult: Sendable {
        /// The endpoint path (e.g., "player", "music/get_queue")
        let endpoint: String

        /// Whether the request succeeded
        let success: Bool

        /// HTTP status code if available
        let statusCode: Int?

        /// Error message if the request failed
        let errorMessage: String?

        /// Top-level keys in the response JSON
        let responseKeys: [String]

        /// Whether authentication appears to be required
        let requiresAuth: Bool

        /// Approximate response size in bytes
        let responseSize: Int

        /// A human-readable summary
        var summary: String {
            if !self.success {
                let authNote = self.requiresAuth ? " (requires authentication)" : ""
                return "❌ \(self.endpoint): \(self.errorMessage ?? "Unknown error")\(authNote)"
            }
            let sizeKB = self.responseSize / 1024
            return "✅ \(self.endpoint): \(self.responseKeys.count) keys, ~\(sizeKB)KB response"
        }
    }

    /// Configuration for an endpoint to explore
    struct EndpointConfig: Sendable {
        let id: String
        let name: String
        let description: String
        let requiresAuth: Bool
        let isImplemented: Bool
        let notes: String?

        init(
            id: String,
            name: String,
            description: String,
            requiresAuth: Bool = false,
            isImplemented: Bool = false,
            notes: String? = nil
        ) {
            self.id = id
            self.name = name
            self.description = description
            self.requiresAuth = requiresAuth
            self.isImplemented = isImplemented
            self.notes = notes
        }
    }

    // MARK: - Known Endpoints Registry

    /// All known browse endpoints for YouTube Music.
    /// This registry serves as the source of truth for available endpoints.
    static let browseEndpoints: [EndpointConfig] = [
        // MARK: - Implemented Endpoints

        EndpointConfig(
            id: "FEmusic_home",
            name: "Home",
            description: "Main home feed with personalized recommendations, mixes, and quick picks",
            requiresAuth: false,
            isImplemented: true,
            notes: "Supports continuation for progressive loading"
        ),
        EndpointConfig(
            id: "FEmusic_explore",
            name: "Explore",
            description: "Explore page with new releases, charts, and moods shortcuts",
            requiresAuth: false,
            isImplemented: true,
            notes: "Supports continuation for progressive loading"
        ),
        EndpointConfig(
            id: "FEmusic_liked_playlists",
            name: "Library Playlists",
            description: "User's saved/created playlists in their library",
            requiresAuth: true,
            isImplemented: true
        ),
        EndpointConfig(
            id: "FEmusic_liked_videos",
            name: "Liked Songs",
            description: "Songs the user has liked (thumbs up)",
            requiresAuth: true,
            isImplemented: true,
            notes: "Returns as playlist detail format"
        ),

        // MARK: - Available (Not Implemented)

        EndpointConfig(
            id: "FEmusic_charts",
            name: "Charts",
            description: "Top songs, albums, trending charts by genre and country",
            requiresAuth: false,
            isImplemented: false,
            notes: "High priority - popular feature"
        ),
        EndpointConfig(
            id: "FEmusic_moods_and_genres",
            name: "Moods & Genres",
            description: "Browse music by mood (Chill, Workout) or genre (Pop, Rock)",
            requiresAuth: false,
            isImplemented: false,
            notes: "Returns grid sections for moods and genres"
        ),
        EndpointConfig(
            id: "FEmusic_new_releases",
            name: "New Releases",
            description: "Recently released albums, singles, and music videos",
            requiresAuth: false,
            isImplemented: false
        ),
        EndpointConfig(
            id: "FEmusic_podcasts",
            name: "Podcasts",
            description: "Podcast discovery and browsing",
            requiresAuth: false,
            isImplemented: false,
            notes: "Lower priority - not core music feature"
        ),
        EndpointConfig(
            id: "FEmusic_history",
            name: "History",
            description: "User's listening history / recently played",
            requiresAuth: true,
            isImplemented: false,
            notes: "High priority - users expect this feature"
        ),
        EndpointConfig(
            id: "FEmusic_library_landing",
            name: "Library Landing",
            description: "Library overview with recent activity",
            requiresAuth: true,
            isImplemented: false,
            notes: "Returns HTTP 200 but only login prompt without auth"
        ),
        EndpointConfig(
            id: "FEmusic_library_albums",
            name: "Library Albums",
            description: "Albums saved to user's library",
            requiresAuth: true,
            isImplemented: false,
            notes: "Returns HTTP 400 without auth+params. Needs sort params from web client."
        ),
        EndpointConfig(
            id: "FEmusic_library_artists",
            name: "Library Artists",
            description: "Artists the user follows/subscribes to",
            requiresAuth: true,
            isImplemented: false,
            notes: "Returns HTTP 400 without auth+params. Needs sort params from web client."
        ),
        EndpointConfig(
            id: "FEmusic_library_songs",
            name: "Library Songs",
            description: "All songs in user's library",
            requiresAuth: true,
            isImplemented: false,
            notes: "Returns HTTP 400 without auth+params. Needs sort params from web client."
        ),
        EndpointConfig(
            id: "FEmusic_recently_played",
            name: "Recently Played",
            description: "Quick access to recently played content",
            requiresAuth: true,
            isImplemented: false,
            notes: "Returns HTTP 400 without auth. May overlap with FEmusic_history."
        ),
        EndpointConfig(
            id: "FEmusic_offline",
            name: "Downloads",
            description: "Downloaded content for offline playback",
            requiresAuth: true,
            isImplemented: false,
            notes: "Desktop web may not support this"
        ),
        EndpointConfig(
            id: "FEmusic_library_privately_owned_landing",
            name: "Uploads Landing",
            description: "User-uploaded music landing page",
            requiresAuth: true,
            isImplemented: false
        ),
        EndpointConfig(
            id: "FEmusic_library_privately_owned_tracks",
            name: "Uploaded Tracks",
            description: "User-uploaded songs",
            requiresAuth: true,
            isImplemented: false
        ),
        EndpointConfig(
            id: "FEmusic_library_privately_owned_albums",
            name: "Uploaded Albums",
            description: "User-uploaded albums",
            requiresAuth: true,
            isImplemented: false
        ),
        EndpointConfig(
            id: "FEmusic_library_privately_owned_artists",
            name: "Uploaded Artists",
            description: "Artists from user-uploaded content",
            requiresAuth: true,
            isImplemented: false
        ),
    ]

    /// All known action endpoints for YouTube Music.
    static let actionEndpoints: [EndpointConfig] = [
        // MARK: - Implemented

        EndpointConfig(
            id: "search",
            name: "Search",
            description: "Search for songs, albums, artists, playlists",
            requiresAuth: false,
            isImplemented: true
        ),
        EndpointConfig(
            id: "music/get_search_suggestions",
            name: "Search Suggestions",
            description: "Autocomplete suggestions for search",
            requiresAuth: false,
            isImplemented: true
        ),
        EndpointConfig(
            id: "next",
            name: "Next / Now Playing",
            description: "Get track info, lyrics browse ID, related tracks, autoplay queue",
            requiresAuth: false,
            isImplemented: true,
            notes: "Used for lyrics, song metadata, and radio queue"
        ),
        EndpointConfig(
            id: "like/like",
            name: "Like",
            description: "Like a song, album, playlist, or artist",
            requiresAuth: true,
            isImplemented: true
        ),
        EndpointConfig(
            id: "like/dislike",
            name: "Dislike",
            description: "Dislike a song",
            requiresAuth: true,
            isImplemented: true
        ),
        EndpointConfig(
            id: "like/removelike",
            name: "Remove Like",
            description: "Remove like/dislike rating from content",
            requiresAuth: true,
            isImplemented: true
        ),
        EndpointConfig(
            id: "feedback",
            name: "Feedback",
            description: "Library add/remove using feedback tokens",
            requiresAuth: true,
            isImplemented: true
        ),
        EndpointConfig(
            id: "subscription/subscribe",
            name: "Subscribe",
            description: "Subscribe to an artist channel",
            requiresAuth: true,
            isImplemented: true
        ),
        EndpointConfig(
            id: "subscription/unsubscribe",
            name: "Unsubscribe",
            description: "Unsubscribe from an artist channel",
            requiresAuth: true,
            isImplemented: true
        ),

        // MARK: - Available (Not Implemented)

        EndpointConfig(
            id: "player",
            name: "Player",
            description: "Get video details, streaming formats, captions",
            requiresAuth: false,
            isImplemented: false,
            notes: "Verified: Returns 17+ keys including videoDetails, streamingData (26 formats), playabilityStatus"
        ),
        EndpointConfig(
            id: "music/get_queue",
            name: "Get Queue",
            description: "Get queue data for video IDs",
            requiresAuth: false,
            isImplemented: false,
            notes: "Verified: Returns queueDatas with playlistPanelVideoRenderer per video"
        ),
        EndpointConfig(
            id: "playlist/get_add_to_playlist",
            name: "Get Add to Playlist",
            description: "Get user's playlists for 'Add to Playlist' menu",
            requiresAuth: true,
            isImplemented: false,
            notes: "Verified: Returns HTTP 401 without auth"
        ),
        EndpointConfig(
            id: "browse/edit_playlist",
            name: "Edit Playlist",
            description: "Add/remove tracks from a playlist",
            requiresAuth: true,
            isImplemented: false,
            notes: "Verified: Returns HTTP 401 without auth"
        ),
        EndpointConfig(
            id: "playlist/create",
            name: "Create Playlist",
            description: "Create a new playlist",
            requiresAuth: true,
            isImplemented: false,
            notes: "Verified: Returns HTTP 401 without auth"
        ),
        EndpointConfig(
            id: "playlist/delete",
            name: "Delete Playlist",
            description: "Delete a playlist",
            requiresAuth: true,
            isImplemented: false
        ),
        EndpointConfig(
            id: "guide",
            name: "Guide",
            description: "Sidebar navigation structure",
            requiresAuth: false,
            isImplemented: false,
            notes: "Low priority - we build our own sidebar"
        ),
        EndpointConfig(
            id: "account/account_menu",
            name: "Account Menu",
            description: "Account settings and profile info",
            requiresAuth: true,
            isImplemented: false
        ),
        EndpointConfig(
            id: "notification/get_notification_menu",
            name: "Notifications",
            description: "User notifications",
            requiresAuth: true,
            isImplemented: false
        ),
        EndpointConfig(
            id: "stats/watchtime",
            name: "Watch Time",
            description: "Listening statistics",
            requiresAuth: true,
            isImplemented: false
        ),
    ]

    // MARK: - Properties

    private let webKitManager: WebKitManager
    private let logger = DiagnosticsLogger.api

    /// YouTube Music API base URL
    private static let baseURL = "https://music.youtube.com/youtubei/v1"

    /// API key (extracted from YouTube Music web client)
    private static let apiKey = "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30"

    /// Client version for WEB_REMIX
    private static let clientVersion = "1.20231204.01.00"

    // MARK: - Initialization

    /// Creates an API explorer instance.
    /// - Parameter webKitManager: The WebKit manager for cookie access
    init(webKitManager: WebKitManager = .shared) {
        self.webKitManager = webKitManager
    }

    // MARK: - Exploration Methods

    /// Explores a browse endpoint and returns structured results.
    /// - Parameter browseId: The browse ID to explore (e.g., "FEmusic_charts")
    /// - Returns: A BrowseResult with information about the endpoint
    func exploreBrowseEndpoint(_ browseId: String) async -> BrowseResult {
        self.logger.info("[APIExplorer] Exploring browse endpoint: \(browseId)")

        let body: [String: Any] = ["browseId": browseId]

        do {
            let (data, statusCode) = try await makeRequest("browse", body: body)

            let responseKeys = Array(data.keys).sorted()
            let (sectionCount, sectionTypes) = self.parseSectionInfo(from: data)

            return BrowseResult(
                browseId: browseId,
                success: true,
                statusCode: statusCode,
                errorMessage: nil,
                responseKeys: responseKeys,
                sectionCount: sectionCount,
                sectionTypes: sectionTypes,
                requiresAuth: false
            )
        } catch let error as ExplorerError {
            return BrowseResult(
                browseId: browseId,
                success: false,
                statusCode: error.statusCode,
                errorMessage: error.message,
                responseKeys: [],
                sectionCount: 0,
                sectionTypes: [],
                requiresAuth: error.statusCode == 401 || error.statusCode == 403
            )
        } catch {
            return BrowseResult(
                browseId: browseId,
                success: false,
                statusCode: nil,
                errorMessage: error.localizedDescription,
                responseKeys: [],
                sectionCount: 0,
                sectionTypes: [],
                requiresAuth: false
            )
        }
    }

    /// Explores an action endpoint and returns structured results.
    /// - Parameters:
    ///   - endpoint: The endpoint path (e.g., "player", "music/get_queue")
    ///   - body: The request body parameters
    /// - Returns: An ActionResult with information about the endpoint
    func exploreActionEndpoint(_ endpoint: String, body: [String: Any]) async -> ActionResult {
        self.logger.info("[APIExplorer] Exploring action endpoint: \(endpoint)")

        do {
            let (data, statusCode) = try await makeRequest(endpoint, body: body)
            let responseKeys = Array(data.keys).sorted()

            // Estimate response size
            let jsonData = try? JSONSerialization.data(withJSONObject: data)
            let responseSize = jsonData?.count ?? 0

            return ActionResult(
                endpoint: endpoint,
                success: true,
                statusCode: statusCode,
                errorMessage: nil,
                responseKeys: responseKeys,
                requiresAuth: false,
                responseSize: responseSize
            )
        } catch let error as ExplorerError {
            return ActionResult(
                endpoint: endpoint,
                success: false,
                statusCode: error.statusCode,
                errorMessage: error.message,
                responseKeys: [],
                requiresAuth: error.statusCode == 401 || error.statusCode == 403,
                responseSize: 0
            )
        } catch {
            return ActionResult(
                endpoint: endpoint,
                success: false,
                statusCode: nil,
                errorMessage: error.localizedDescription,
                responseKeys: [],
                requiresAuth: false,
                responseSize: 0
            )
        }
    }

    /// Explores all known browse endpoints and returns results.
    /// - Parameter includeImplemented: Whether to include already-implemented endpoints
    /// - Returns: Array of BrowseResult for each endpoint
    func exploreAllBrowseEndpoints(includeImplemented: Bool = false) async -> [BrowseResult] {
        let endpoints = Self.browseEndpoints.filter { includeImplemented || !$0.isImplemented }
        var results: [BrowseResult] = []

        for endpoint in endpoints {
            let result = await exploreBrowseEndpoint(endpoint.id)
            results.append(result)
        }

        return results
    }

    /// Generates a markdown report of all endpoints.
    /// - Returns: A formatted markdown string documenting all endpoints
    func generateEndpointReport() async -> String {
        var report = """
        # YouTube Music API Endpoint Report

        Generated: \(ISO8601DateFormatter().string(from: Date()))

        ## Browse Endpoints

        | ID | Name | Auth | Implemented | Status |
        |----|------|------|-------------|--------|

        """

        // Add browse endpoints
        for endpoint in Self.browseEndpoints {
            let authIcon = endpoint.requiresAuth ? "🔐" : "🌐"
            let implIcon = endpoint.isImplemented ? "✅" : "⏳"
            let result = await exploreBrowseEndpoint(endpoint.id)
            let statusIcon = result.success ? "✅" : (result.requiresAuth ? "🔒" : "❌")

            report += "| `\(endpoint.id)` | \(endpoint.name) | \(authIcon) | \(implIcon) | \(statusIcon) |\n"
        }

        report += """

        ## Action Endpoints

        | Endpoint | Name | Auth | Implemented |
        |----------|------|------|-------------|

        """

        // Add action endpoints
        for endpoint in Self.actionEndpoints {
            let authIcon = endpoint.requiresAuth ? "🔐" : "🌐"
            let implIcon = endpoint.isImplemented ? "✅" : "⏳"

            report += "| `\(endpoint.id)` | \(endpoint.name) | \(authIcon) | \(implIcon) |\n"
        }

        report += """

        ## Legend

        - 🌐 = No authentication required
        - 🔐 = Authentication required
        - ✅ = Implemented / Working
        - ⏳ = Not yet implemented
        - 🔒 = Auth required (returned 401/403)
        - ❌ = Error (not auth-related)

        """

        return report
    }

    // MARK: - Private Methods

    /// Internal error type for exploration
    private struct ExplorerError: Error {
        let message: String
        let statusCode: Int?
    }

    /// Makes an API request and returns the parsed response.
    private func makeRequest(_ endpoint: String, body: [String: Any]) async throws -> ([String: Any], Int) {
        let urlString = "\(Self.baseURL)/\(endpoint)?key=\(Self.apiKey)&prettyPrint=false"
        guard let url = URL(string: urlString) else {
            throw ExplorerError(message: "Invalid URL", statusCode: nil)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Add headers
        let headers = try await buildHeaders()
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Build body with context
        var fullBody = body
        fullBody["context"] = self.buildContext()

        request.httpBody = try JSONSerialization.data(withJSONObject: fullBody)

        let session = URLSession.shared
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExplorerError(message: "Invalid response", statusCode: nil)
        }

        let statusCode = httpResponse.statusCode

        guard (200 ... 299).contains(statusCode) else {
            throw ExplorerError(
                message: "HTTP \(statusCode)",
                statusCode: statusCode
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ExplorerError(message: "Invalid JSON", statusCode: statusCode)
        }

        return (json, statusCode)
    }

    /// Builds request headers including authentication if available.
    private func buildHeaders() async throws -> [String: String] {
        var headers: [String: String] = [
            "Content-Type": "application/json",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
        ]

        // Try to add auth headers if cookies are available
        if let cookieHeader = await webKitManager.cookieHeader(for: "youtube.com"),
           let sapisid = await webKitManager.getSAPISID()
        {
            let origin = WebKitManager.origin
            let timestamp = Int(Date().timeIntervalSince1970)
            let hashInput = "\(timestamp) \(sapisid) \(origin)"

            // Import CryptoKit for SHA1
            let hashData = Data(hashInput.utf8)
            var sha1 = [UInt8](repeating: 0, count: 20)
            hashData.withUnsafeBytes { buffer in
                _ = CC_SHA1(buffer.baseAddress, CC_LONG(buffer.count), &sha1)
            }
            let hash = sha1.map { String(format: "%02x", $0) }.joined()
            let sapisidhash = "\(timestamp)_\(hash)"

            headers["Cookie"] = cookieHeader
            headers["Authorization"] = "SAPISIDHASH \(sapisidhash)"
            headers["Origin"] = origin
            headers["Referer"] = origin
            headers["X-Goog-AuthUser"] = "0"
            headers["X-Origin"] = origin
        }

        return headers
    }

    /// Builds the standard API context.
    private func buildContext() -> [String: Any] {
        [
            "client": [
                "clientName": "WEB_REMIX",
                "clientVersion": Self.clientVersion,
                "hl": "en",
                "gl": "US",
                "browserName": "Safari",
                "browserVersion": "17.0",
                "osName": "Macintosh",
                "osVersion": "10_15_7",
                "platform": "DESKTOP",
            ],
            "user": [
                "lockedSafetyMode": false,
            ],
        ]
    }

    /// Parses section information from a browse response.
    private func parseSectionInfo(from data: [String: Any]) -> (count: Int, types: [String]) {
        var sectionTypes: Set<String> = []
        var sectionCount = 0

        // Navigate to contents
        guard let contents = data["contents"] as? [String: Any] else {
            return (0, [])
        }

        // Try singleColumnBrowseResultsRenderer
        if let singleColumn = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
           let tabs = singleColumn["tabs"] as? [[String: Any]]
        {
            for tab in tabs {
                if let tabRenderer = tab["tabRenderer"] as? [String: Any],
                   let tabContent = tabRenderer["content"] as? [String: Any],
                   let sectionListRenderer = tabContent["sectionListRenderer"] as? [String: Any],
                   let sections = sectionListRenderer["contents"] as? [[String: Any]]
                {
                    sectionCount = sections.count
                    for section in sections {
                        sectionTypes.formUnion(section.keys)
                    }
                }
            }
        }

        // Try tabbedSearchResultsRenderer (for search)
        if let tabbedSearch = contents["tabbedSearchResultsRenderer"] as? [String: Any],
           let tabs = tabbedSearch["tabs"] as? [[String: Any]]
        {
            for tab in tabs {
                if let tabRenderer = tab["tabRenderer"] as? [String: Any],
                   let tabContent = tabRenderer["content"] as? [String: Any],
                   let sectionListRenderer = tabContent["sectionListRenderer"] as? [String: Any],
                   let sections = sectionListRenderer["contents"] as? [[String: Any]]
                {
                    sectionCount += sections.count
                    for section in sections {
                        sectionTypes.formUnion(section.keys)
                    }
                }
            }
        }

        return (sectionCount, Array(sectionTypes).sorted())
    }
}

// MARK: - CommonCrypto Import for SHA1

import CommonCrypto
