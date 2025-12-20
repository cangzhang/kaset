import CryptoKit
import Foundation
import os

/// Client for making authenticated requests to YouTube Music's internal API.
@MainActor
final class YTMusicClient: YTMusicClientProtocol {
    private let authService: AuthService
    private let webKitManager: WebKitManager
    private let session: URLSession
    private let logger = DiagnosticsLogger.api

    /// YouTube Music API base URL.
    private static let baseURL = "https://music.youtube.com/youtubei/v1"

    /// API key used in requests (extracted from YouTube Music web client).
    private static let apiKey = "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30"

    /// Client version for WEB_REMIX.
    private static let clientVersion = "1.20231204.01.00"

    init(authService: AuthService, webKitManager: WebKitManager = .shared) {
        self.authService = authService
        self.webKitManager = webKitManager

        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
        ]
        session = URLSession(configuration: configuration)
    }

    // MARK: - Public API Methods

    /// Fetches the home page content with all sections (including continuations).
    func getHome() async throws -> HomeResponse {
        logger.info("Fetching home page")

        let body: [String: Any] = [
            "browseId": "FEmusic_home",
        ]

        let data = try await request("browse", body: body, ttl: APICache.TTL.home)
        var response = HomeResponseParser.parse(data)

        // Fetch continuation sections if available
        var continuationToken = HomeResponseParser.extractContinuationToken(from: data)
        var continuationCount = 0
        let maxContinuations = 10 // Prevent infinite loops

        while let token = continuationToken, continuationCount < maxContinuations {
            continuationCount += 1
            logger.info("Fetching home continuation \(continuationCount)")

            do {
                let continuationData = try await requestContinuation(token)
                let additionalSections = HomeResponseParser.parseContinuation(continuationData)
                response = HomeResponse(sections: response.sections + additionalSections)
                continuationToken = HomeResponseParser.extractContinuationTokenFromContinuation(continuationData)
            } catch {
                logger.warning("Failed to fetch continuation: \(error.localizedDescription)")
                break
            }
        }

        logger.info("Total home sections after continuations: \(response.sections.count)")
        return response
    }

    /// Fetches the explore page content with all sections.
    func getExplore() async throws -> HomeResponse {
        logger.info("Fetching explore page")

        let body: [String: Any] = [
            "browseId": "FEmusic_explore",
        ]

        let data = try await request("browse", body: body, ttl: APICache.TTL.home)
        var response = HomeResponseParser.parse(data)

        // Fetch continuation sections if available
        var continuationToken = HomeResponseParser.extractContinuationToken(from: data)
        var continuationCount = 0
        let maxContinuations = 10

        while let token = continuationToken, continuationCount < maxContinuations {
            continuationCount += 1
            logger.info("Fetching explore continuation \(continuationCount)")

            do {
                let continuationData = try await requestContinuation(token)
                let additionalSections = HomeResponseParser.parseContinuation(continuationData)
                response = HomeResponse(sections: response.sections + additionalSections)
                continuationToken = HomeResponseParser.extractContinuationTokenFromContinuation(continuationData)
            } catch {
                logger.warning("Failed to fetch continuation: \(error.localizedDescription)")
                break
            }
        }

        logger.info("Total explore sections after continuations: \(response.sections.count)")
        return response
    }

    /// Makes a continuation request.
    private func requestContinuation(_ token: String) async throws -> [String: Any] {
        let body: [String: Any] = [
            "continuation": token,
        ]
        return try await request("browse", body: body)
    }

    /// Searches for content.
    func search(query: String) async throws -> SearchResponse {
        logger.info("Searching for: \(query)")

        let body: [String: Any] = [
            "query": query,
        ]

        let data = try await request("search", body: body, ttl: APICache.TTL.search)
        let response = SearchResponseParser.parse(data)
        logger.info("Search found \(response.songs.count) songs, \(response.albums.count) albums, \(response.artists.count) artists, \(response.playlists.count) playlists")
        return response
    }

    /// Fetches the user's library playlists.
    func getLibraryPlaylists() async throws -> [Playlist] {
        logger.info("Fetching library playlists")

        let body: [String: Any] = [
            "browseId": "FEmusic_liked_playlists",
        ]

        let data = try await request("browse", body: body)
        let playlists = PlaylistParser.parseLibraryPlaylists(data)
        logger.info("Parsed \(playlists.count) library playlists")
        return playlists
    }

    /// Fetches playlist details including tracks.
    func getPlaylist(id: String) async throws -> PlaylistDetail {
        logger.info("Fetching playlist: \(id)")

        // Handle different ID formats:
        // - VL... = playlist (already has prefix)
        // - PL... = playlist (needs VL prefix)
        // - RD... = radio/mix (use as-is)
        // - OLAK... = album (use as-is)
        // - MPRE... = album (use as-is)
        let browseId: String = if id.hasPrefix("VL") || id.hasPrefix("RD") || id.hasPrefix("OLAK") || id.hasPrefix("MPRE") || id.hasPrefix("UC") {
            id
        } else if id.hasPrefix("PL") {
            "VL\(id)"
        } else {
            "VL\(id)"
        }

        let body: [String: Any] = [
            "browseId": browseId,
        ]

        let data = try await request("browse", body: body, ttl: APICache.TTL.playlist)

        // Log top-level keys for debugging
        let topKeys = Array(data.keys)
        logger.debug("Playlist response top-level keys: \(topKeys)")

        let detail = PlaylistParser.parsePlaylistDetail(data, playlistId: id)
        logger.info("Parsed playlist '\(detail.title)' with \(detail.tracks.count) tracks")
        return detail
    }

    /// Fetches artist details including their songs and albums.
    func getArtist(id: String) async throws -> ArtistDetail {
        logger.info("Fetching artist: \(id)")

        let body: [String: Any] = [
            "browseId": id,
        ]

        let data = try await request("browse", body: body, ttl: APICache.TTL.artist)

        let topKeys = Array(data.keys)
        logger.debug("Artist response top-level keys: \(topKeys)")

        let detail = ArtistParser.parseArtistDetail(data, artistId: id)
        logger.info("Parsed artist '\(detail.artist.name)' with \(detail.songs.count) songs and \(detail.albums.count) albums")
        return detail
    }

    // MARK: - Like/Library Actions

    /// Rates a song (like/dislike/indifferent).
    /// - Parameters:
    ///   - videoId: The video ID of the song to rate
    ///   - rating: The rating to apply (like, dislike, or indifferent to remove rating)
    func rateSong(videoId: String, rating: LikeStatus) async throws {
        logger.info("Rating song \(videoId) with \(rating.rawValue)")

        let body: [String: Any] = [
            "target": ["videoId": videoId],
        ]

        // Endpoint varies by rating type
        let endpoint = switch rating {
        case .like:
            "like/like"
        case .dislike:
            "like/dislike"
        case .indifferent:
            "like/removelike"
        }

        _ = try await request(endpoint, body: body)
        logger.info("Successfully rated song \(videoId)")

        // Invalidate liked playlist cache so UI updates immediately
        APICache.shared.invalidate(matching: "browse:")
    }

    /// Adds or removes a song from the user's library.
    /// - Parameter feedbackTokens: Tokens obtained from song metadata (use add token to add, remove token to remove)
    func editSongLibraryStatus(feedbackTokens: [String]) async throws {
        guard !feedbackTokens.isEmpty else {
            logger.warning("No feedback tokens provided for library edit")
            return
        }

        logger.info("Editing song library status with \(feedbackTokens.count) tokens")

        let body: [String: Any] = [
            "feedbackTokens": feedbackTokens,
        ]

        _ = try await request("feedback", body: body)
        logger.info("Successfully edited library status")
    }

    /// Adds a playlist to the user's library using the like/like endpoint.
    /// This is equivalent to the "Add to Library" action in YouTube Music.
    /// - Parameter playlistId: The playlist ID to add to library
    func subscribeToPlaylist(playlistId: String) async throws {
        logger.info("Adding playlist to library: \(playlistId)")

        // Remove VL prefix if present for the API call
        let cleanId = playlistId.hasPrefix("VL") ? String(playlistId.dropFirst(2)) : playlistId

        let body: [String: Any] = [
            "target": ["playlistId": cleanId],
        ]

        _ = try await request("like/like", body: body)
        logger.info("Successfully added playlist \(playlistId) to library")

        // Invalidate library cache so UI updates
        APICache.shared.invalidate(matching: "browse:")
    }

    /// Removes a playlist from the user's library using the like/removelike endpoint.
    /// This is equivalent to the "Remove from Library" action in YouTube Music.
    /// - Parameter playlistId: The playlist ID to remove from library
    func unsubscribeFromPlaylist(playlistId: String) async throws {
        logger.info("Removing playlist from library: \(playlistId)")

        // Remove VL prefix if present for the API call
        let cleanId = playlistId.hasPrefix("VL") ? String(playlistId.dropFirst(2)) : playlistId

        let body: [String: Any] = [
            "target": ["playlistId": cleanId],
        ]

        _ = try await request("like/removelike", body: body)
        logger.info("Successfully removed playlist \(playlistId) from library")

        // Invalidate library cache so UI updates
        APICache.shared.invalidate(matching: "browse:")
    }

    // MARK: - Private Methods

    /// Builds authentication headers for API requests.
    private func buildAuthHeaders() async throws -> [String: String] {
        guard let cookieHeader = await webKitManager.cookieHeader(for: "youtube.com") else {
            throw YTMusicError.notAuthenticated
        }

        guard let sapisid = await webKitManager.getSAPISID() else {
            throw YTMusicError.authExpired
        }

        // Compute SAPISIDHASH
        let origin = WebKitManager.origin
        let timestamp = Int(Date().timeIntervalSince1970)
        let hashInput = "\(timestamp) \(sapisid) \(origin)"
        let hash = Insecure.SHA1.hash(data: Data(hashInput.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        let sapisidhash = "\(timestamp)_\(hash)"

        return [
            "Cookie": cookieHeader,
            "Authorization": "SAPISIDHASH \(sapisidhash)",
            "Origin": origin,
            "Referer": origin,
            "Content-Type": "application/json",
            "X-Goog-AuthUser": "0",
            "X-Origin": origin,
        ]
    }

    /// Builds the standard context payload.
    private func buildContext() -> [String: Any] {
        [
            "client": [
                "clientName": "WEB_REMIX",
                "clientVersion": Self.clientVersion,
                "hl": "en",
                "gl": "US",
                "experimentIds": [],
                "experimentsToken": "",
                "browserName": "Safari",
                "browserVersion": "17.0",
                "osName": "Macintosh",
                "osVersion": "10_15_7",
                "platform": "DESKTOP",
                "userAgent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                "utcOffsetMinutes": -TimeZone.current.secondsFromGMT() / 60,
            ],
            "user": [
                "lockedSafetyMode": false,
            ],
        ]
    }

    /// Makes an authenticated request to the API with optional caching and retry.
    private func request(_ endpoint: String, body: [String: Any], ttl: TimeInterval? = nil) async throws -> [String: Any] {
        // Generate cache key from endpoint and body
        let cacheKey = "\(endpoint):\(body.description.hashValue)"

        // Check cache first
        if ttl != nil, let cached = APICache.shared.get(key: cacheKey) {
            logger.debug("Cache hit for \(endpoint)")
            return cached
        }

        // Execute with retry policy
        let json = try await RetryPolicy.default.execute { [self] in
            try await performRequest(endpoint, body: body)
        }

        // Cache response if TTL specified
        if let ttl {
            APICache.shared.set(key: cacheKey, data: json, ttl: ttl)
        }

        return json
    }

    /// Performs the actual network request.
    private func performRequest(_ endpoint: String, body: [String: Any]) async throws -> [String: Any] {
        let urlString = "\(Self.baseURL)/\(endpoint)?key=\(Self.apiKey)&prettyPrint=false"
        guard let url = URL(string: urlString) else {
            throw YTMusicError.unknown(message: "Invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Add auth headers
        let headers = try await buildAuthHeaders()
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Build request body with context
        var fullBody = body
        fullBody["context"] = buildContext()

        request.httpBody = try JSONSerialization.data(withJSONObject: fullBody)

        logger.debug("Making request to \(endpoint)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw YTMusicError.networkError(underlying: URLError(.badServerResponse))
        }

        // Handle auth errors
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            logger.error("Auth error: HTTP \(httpResponse.statusCode)")
            authService.sessionExpired()
            throw YTMusicError.authExpired
        }

        // Handle other errors
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            logger.error("API error: HTTP \(httpResponse.statusCode)")
            throw YTMusicError.apiError(
                message: "HTTP \(httpResponse.statusCode)",
                code: httpResponse.statusCode
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw YTMusicError.parseError(message: "Response is not a JSON object")
        }

        return json
    }
}
