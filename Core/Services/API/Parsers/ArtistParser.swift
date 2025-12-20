import Foundation
import os

/// Parser for artist-related responses from YouTube Music API.
enum ArtistParser {
    private static let logger = DiagnosticsLogger.api

    /// Parses artist detail from browse response.
    static func parseArtistDetail(_ data: [String: Any], artistId: String) -> ArtistDetail {
        var name = "Unknown Artist"
        var description: String?
        var thumbnailURL: URL?
        var songs: [Song] = []
        var albums: [Album] = []

        // Parse header
        parseArtistHeader(data, name: &name, description: &description, thumbnailURL: &thumbnailURL)

        // Parse content sections for songs and albums
        if let contents = data["contents"] as? [String: Any],
           let singleColumnBrowseResults = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
           let tabs = singleColumnBrowseResults["tabs"] as? [[String: Any]],
           let firstTab = tabs.first,
           let tabRenderer = firstTab["tabRenderer"] as? [String: Any],
           let tabContent = tabRenderer["content"] as? [String: Any],
           let sectionListRenderer = tabContent["sectionListRenderer"] as? [String: Any],
           let sectionContents = sectionListRenderer["contents"] as? [[String: Any]]
        {
            for sectionData in sectionContents {
                // Parse songs from musicShelfRenderer
                if let shelfRenderer = sectionData["musicShelfRenderer"] as? [String: Any],
                   let shelfContents = shelfRenderer["contents"] as? [[String: Any]]
                {
                    songs.append(contentsOf: parseTracksFromItems(shelfContents))
                }

                // Parse albums from musicCarouselShelfRenderer
                if let carouselRenderer = sectionData["musicCarouselShelfRenderer"] as? [String: Any],
                   let carouselContents = carouselRenderer["contents"] as? [[String: Any]]
                {
                    for itemData in carouselContents {
                        if let twoRowRenderer = itemData["musicTwoRowItemRenderer"] as? [String: Any],
                           let album = parseAlbumFromTwoRowRenderer(twoRowRenderer)
                        {
                            albums.append(album)
                        }
                    }
                }
            }
        }

        let artist = Artist(id: artistId, name: name, thumbnailURL: thumbnailURL)

        return ArtistDetail(
            artist: artist,
            description: description,
            songs: songs,
            albums: albums,
            thumbnailURL: thumbnailURL
        )
    }

    // MARK: - Header Parsing

    private static func parseArtistHeader(
        _ data: [String: Any],
        name: inout String,
        description: inout String?,
        thumbnailURL: inout URL?
    ) {
        // Try musicImmersiveHeaderRenderer (common for artist pages)
        if let header = data["header"] as? [String: Any],
           let immersiveHeader = header["musicImmersiveHeaderRenderer"] as? [String: Any]
        {
            if let text = ParsingHelpers.extractTitle(from: immersiveHeader) {
                name = text
            }

            if let descData = immersiveHeader["description"] as? [String: Any],
               let runs = descData["runs"] as? [[String: Any]]
            {
                description = runs.compactMap { $0["text"] as? String }.joined()
            }

            let thumbnails = ParsingHelpers.extractThumbnails(from: immersiveHeader)
            thumbnailURL = thumbnails.last.flatMap { URL(string: $0) }
        }

        // Try musicVisualHeaderRenderer (alternative header format)
        if name == "Unknown Artist",
           let header = data["header"] as? [String: Any],
           let visualHeader = header["musicVisualHeaderRenderer"] as? [String: Any]
        {
            if let text = ParsingHelpers.extractTitle(from: visualHeader) {
                name = text
            }

            let thumbnails = ParsingHelpers.extractThumbnails(from: visualHeader)
            thumbnailURL = thumbnails.last.flatMap { URL(string: $0) }
        }
    }

    // MARK: - Content Parsing

    private static func parseTracksFromItems(_ items: [[String: Any]], fallbackThumbnailURL: URL? = nil) -> [Song] {
        var tracks: [Song] = []

        for itemData in items {
            guard let responsiveRenderer = itemData["musicResponsiveListItemRenderer"] as? [String: Any] else {
                continue
            }

            guard let videoId = ParsingHelpers.extractVideoId(from: responsiveRenderer) else {
                continue
            }

            let title = ParsingHelpers.extractTitleFromFlexColumns(responsiveRenderer) ?? "Unknown"
            let artists = ParsingHelpers.extractArtistsFromFlexColumns(responsiveRenderer)
            let thumbnails = ParsingHelpers.extractThumbnails(from: responsiveRenderer)
            let thumbnailURL = thumbnails.last.flatMap { URL(string: $0) } ?? fallbackThumbnailURL
            let duration = ParsingHelpers.extractDurationFromFlexColumns(responsiveRenderer)

            let track = Song(
                id: videoId,
                title: title,
                artists: artists,
                album: nil,
                duration: duration,
                thumbnailURL: thumbnailURL,
                videoId: videoId
            )
            tracks.append(track)
        }

        return tracks
    }

    private static func parseAlbumFromTwoRowRenderer(_ data: [String: Any]) -> Album? {
        guard let navigationEndpoint = data["navigationEndpoint"] as? [String: Any],
              let browseEndpoint = navigationEndpoint["browseEndpoint"] as? [String: Any],
              let browseId = browseEndpoint["browseId"] as? String,
              browseId.hasPrefix("MPRE") || browseId.hasPrefix("OLAK")
        else {
            return nil
        }

        let thumbnails = ParsingHelpers.extractThumbnails(from: data)
        let thumbnailURL = thumbnails.last.flatMap { URL(string: $0) }
        let title = ParsingHelpers.extractTitle(from: data) ?? "Unknown Album"

        var year: String?
        if let subtitleData = data["subtitle"] as? [String: Any],
           let runs = subtitleData["runs"] as? [[String: Any]]
        {
            // Year is typically the last item in subtitle
            year = runs.last?["text"] as? String
        }

        return Album(
            id: browseId,
            title: title,
            artists: nil,
            thumbnailURL: thumbnailURL,
            year: year,
            trackCount: nil
        )
    }
}
