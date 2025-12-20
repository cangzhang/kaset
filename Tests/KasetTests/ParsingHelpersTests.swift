import XCTest
@testable import Kaset

/// Tests for the ParsingHelpers.
final class ParsingHelpersTests: XCTestCase {
    // MARK: - Chart Section Detection

    func testIsChartSectionWithChart() {
        XCTAssertTrue(ParsingHelpers.isChartSection("Top Charts"))
        XCTAssertTrue(ParsingHelpers.isChartSection("Weekly Top 50"))
        XCTAssertTrue(ParsingHelpers.isChartSection("Trending Now"))
        XCTAssertTrue(ParsingHelpers.isChartSection("Daily Top 100"))
    }

    func testIsChartSectionWithNonChart() {
        XCTAssertFalse(ParsingHelpers.isChartSection("Quick picks"))
        XCTAssertFalse(ParsingHelpers.isChartSection("New releases"))
        XCTAssertFalse(ParsingHelpers.isChartSection("Recommended"))
    }

    // MARK: - URL Normalization

    func testNormalizeURLWithProtocolRelative() {
        let result = ParsingHelpers.normalizeURL("//example.com/image.jpg")
        XCTAssertEqual(result, "https://example.com/image.jpg")
    }

    func testNormalizeURLWithFullURL() {
        let result = ParsingHelpers.normalizeURL("https://example.com/image.jpg")
        XCTAssertEqual(result, "https://example.com/image.jpg")
    }

    // MARK: - Thumbnail Extraction

    func testExtractThumbnailsFromMusicThumbnailRenderer() {
        let data: [String: Any] = [
            "thumbnail": [
                "musicThumbnailRenderer": [
                    "thumbnail": [
                        "thumbnails": [
                            ["url": "//example.com/small.jpg"],
                            ["url": "//example.com/large.jpg"],
                        ],
                    ],
                ],
            ],
        ]

        let thumbnails = ParsingHelpers.extractThumbnails(from: data)

        XCTAssertEqual(thumbnails.count, 2)
        XCTAssertEqual(thumbnails.first, "https://example.com/small.jpg")
        XCTAssertEqual(thumbnails.last, "https://example.com/large.jpg")
    }

    func testExtractThumbnailsFromEmptyData() {
        let data: [String: Any] = [:]

        let thumbnails = ParsingHelpers.extractThumbnails(from: data)

        XCTAssertTrue(thumbnails.isEmpty)
    }

    // MARK: - Title Extraction

    func testExtractTitle() {
        let data: [String: Any] = [
            "title": [
                "runs": [
                    ["text": "Test Title"],
                ],
            ],
        ]

        let title = ParsingHelpers.extractTitle(from: data)

        XCTAssertEqual(title, "Test Title")
    }

    func testExtractTitleWithCustomKey() {
        let data: [String: Any] = [
            "name": [
                "runs": [
                    ["text": "Custom Name"],
                ],
            ],
        ]

        let title = ParsingHelpers.extractTitle(from: data, key: "name")

        XCTAssertEqual(title, "Custom Name")
    }

    func testExtractTitleFromEmptyData() {
        let data: [String: Any] = [:]

        let title = ParsingHelpers.extractTitle(from: data)

        XCTAssertNil(title)
    }

    // MARK: - Artist Extraction

    func testExtractArtists() {
        let data: [String: Any] = [
            "subtitle": [
                "runs": [
                    ["text": "Artist 1", "navigationEndpoint": ["browseEndpoint": ["browseId": "UC1"]]],
                    ["text": " & "],
                    ["text": "Artist 2", "navigationEndpoint": ["browseEndpoint": ["browseId": "UC2"]]],
                ],
            ],
        ]

        let artists = ParsingHelpers.extractArtists(from: data)

        XCTAssertEqual(artists.count, 2)
        XCTAssertEqual(artists[0].name, "Artist 1")
        XCTAssertEqual(artists[0].id, "UC1")
        XCTAssertEqual(artists[1].name, "Artist 2")
    }

    func testExtractArtistsFiltersSeparators() {
        let data: [String: Any] = [
            "subtitle": [
                "runs": [
                    ["text": "Artist"],
                    ["text": " • "],
                    ["text": "Song"],
                ],
            ],
        ]

        let artists = ParsingHelpers.extractArtists(from: data)

        XCTAssertEqual(artists.count, 2)
        XCTAssertEqual(artists[0].name, "Artist")
        XCTAssertEqual(artists[1].name, "Song")
    }

    // MARK: - Video ID Extraction

    func testExtractVideoIdFromPlaylistItemData() {
        let data: [String: Any] = [
            "playlistItemData": ["videoId": "abc123"],
        ]

        let videoId = ParsingHelpers.extractVideoId(from: data)

        XCTAssertEqual(videoId, "abc123")
    }

    func testExtractVideoIdFromWatchEndpoint() {
        let data: [String: Any] = [
            "navigationEndpoint": [
                "watchEndpoint": ["videoId": "xyz789"],
            ],
        ]

        let videoId = ParsingHelpers.extractVideoId(from: data)

        XCTAssertEqual(videoId, "xyz789")
    }

    func testExtractVideoIdFromOverlay() {
        let data: [String: Any] = [
            "overlay": [
                "musicItemThumbnailOverlayRenderer": [
                    "content": [
                        "musicPlayButtonRenderer": [
                            "playNavigationEndpoint": [
                                "watchEndpoint": ["videoId": "overlay123"],
                            ],
                        ],
                    ],
                ],
            ],
        ]

        let videoId = ParsingHelpers.extractVideoId(from: data)

        XCTAssertEqual(videoId, "overlay123")
    }

    // MARK: - Browse ID Extraction

    func testExtractBrowseId() {
        let data: [String: Any] = [
            "navigationEndpoint": [
                "browseEndpoint": ["browseId": "VLPL12345"],
            ],
        ]

        let browseId = ParsingHelpers.extractBrowseId(from: data)

        XCTAssertEqual(browseId, "VLPL12345")
    }

    // MARK: - Duration Parsing

    func testParseDurationMinutesSeconds() {
        let duration = ParsingHelpers.parseDuration("3:45")

        XCTAssertEqual(duration, 225) // 3 * 60 + 45
    }

    func testParseDurationHoursMinutesSeconds() {
        let duration = ParsingHelpers.parseDuration("1:30:00")

        XCTAssertEqual(duration, 5400) // 1 * 3600 + 30 * 60
    }

    func testParseDurationInvalid() {
        let duration = ParsingHelpers.parseDuration("invalid")

        XCTAssertNil(duration)
    }

    // MARK: - Flex Column Extraction

    func testExtractTitleFromFlexColumns() {
        let data: [String: Any] = [
            "flexColumns": [
                [
                    "musicResponsiveListItemFlexColumnRenderer": [
                        "text": [
                            "runs": [["text": "Song Title"]],
                        ],
                    ],
                ],
            ],
        ]

        let title = ParsingHelpers.extractTitleFromFlexColumns(data)

        XCTAssertEqual(title, "Song Title")
    }

    func testExtractSubtitleFromFlexColumns() {
        let data: [String: Any] = [
            "flexColumns": [
                [
                    "musicResponsiveListItemFlexColumnRenderer": [
                        "text": ["runs": [["text": "Title"]]],
                    ],
                ],
                [
                    "musicResponsiveListItemFlexColumnRenderer": [
                        "text": [
                            "runs": [
                                ["text": "Artist"],
                                ["text": " • "],
                                ["text": "Album"],
                            ],
                        ],
                    ],
                ],
            ],
        ]

        let subtitle = ParsingHelpers.extractSubtitleFromFlexColumns(data)

        XCTAssertEqual(subtitle, "Artist • Album")
    }

    func testExtractArtistsFromFlexColumns() {
        let data: [String: Any] = [
            "flexColumns": [
                [
                    "musicResponsiveListItemFlexColumnRenderer": [
                        "text": ["runs": [["text": "Title"]]],
                    ],
                ],
                [
                    "musicResponsiveListItemFlexColumnRenderer": [
                        "text": [
                            "runs": [
                                ["text": "Artist Name", "navigationEndpoint": ["browseEndpoint": ["browseId": "UC123"]]],
                            ],
                        ],
                    ],
                ],
            ],
        ]

        let artists = ParsingHelpers.extractArtistsFromFlexColumns(data)

        XCTAssertEqual(artists.count, 1)
        XCTAssertEqual(artists.first?.name, "Artist Name")
        XCTAssertEqual(artists.first?.id, "UC123")
    }
}
