import XCTest

/// Base class for Kaset UI tests.
/// Provides common setup, launch configuration, and helper methods.
class KasetUITestCase: XCTestCase {
    /// The application under test.
    var app: XCUIApplication!

    // MARK: - Setup / Teardown

    override func setUpWithError() throws {
        try super.setUpWithError()

        // Stop immediately when a failure occurs
        continueAfterFailure = false

        // Create new app instance
        app = XCUIApplication()

        // Add UI test mode arguments
        app.launchArguments.append("-UITestMode")
        app.launchArguments.append("-SkipAuth")

        // Disable animations for faster, more reliable tests
        app.launchArguments.append("-UIAnimationsDisabled")
    }

    override func tearDownWithError() throws {
        app = nil
        try super.tearDownWithError()
    }

    // MARK: - Launch Helpers

    /// Launches the app with mock home sections.
    func launchWithMockHome(sectionCount: Int = 3, itemsPerSection: Int = 5) {
        let sections = (0 ..< sectionCount).map { sectionIndex in
            [
                "id": "section-\(sectionIndex)",
                "title": "Test Section \(sectionIndex)",
                "items": (0 ..< itemsPerSection).map { itemIndex in
                    [
                        "type": "song",
                        "id": "song-\(sectionIndex)-\(itemIndex)",
                        "title": "Song \(itemIndex)",
                        "artist": "Artist \(itemIndex)",
                        "videoId": "video-\(sectionIndex)-\(itemIndex)",
                    ]
                },
            ]
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: sections),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            app.launchEnvironment["MOCK_HOME_SECTIONS"] = jsonString
        }

        app.launch()
    }

    /// Launches the app with mock search results.
    func launchWithMockSearch(songCount: Int = 5) {
        let songs = (0 ..< songCount).map { index in
            [
                "id": "search-song-\(index)",
                "title": "Search Result \(index)",
                "artist": "Search Artist \(index)",
                "videoId": "search-video-\(index)",
            ]
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: ["songs": songs]),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            app.launchEnvironment["MOCK_SEARCH_RESULTS"] = jsonString
        }

        app.launch()
    }

    /// Launches the app with mock library playlists.
    func launchWithMockLibrary(playlistCount: Int = 3) {
        let playlists = (0 ..< playlistCount).map { index in
            [
                "id": "playlist-\(index)",
                "title": "Playlist \(index)",
                "trackCount": 10 + index,
            ]
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: playlists),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            app.launchEnvironment["MOCK_PLAYLISTS"] = jsonString
        }

        app.launch()
    }

    /// Launches the app with a mock current track (player has something playing).
    func launchWithMockPlayer(isPlaying: Bool = true) {
        let track: [String: Any] = [
            "id": "current-track",
            "title": "Now Playing Song",
            "artist": "Current Artist",
            "videoId": "current-video",
            "duration": 180,
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: track),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            app.launchEnvironment["MOCK_CURRENT_TRACK"] = jsonString
        }
        app.launchEnvironment["MOCK_IS_PLAYING"] = isPlaying ? "true" : "false"

        app.launch()
    }

    /// Launches the app with default configuration (logged in, no specific mock data).
    func launchDefault() {
        app.launch()
    }

    // MARK: - Wait Helpers

    /// Waits for an element to exist with a timeout.
    @discardableResult
    func waitForElement(
        _ element: XCUIElement,
        timeout: TimeInterval = 5,
        file: StaticString = #file,
        line: UInt = #line
    ) -> Bool {
        let predicate = NSPredicate(format: "exists == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)

        if result != .completed {
            XCTFail("Timed out waiting for element: \(element)", file: file, line: line)
            return false
        }
        return true
    }

    /// Waits for an element to be hittable (visible and interactable).
    @discardableResult
    func waitForHittable(
        _ element: XCUIElement,
        timeout: TimeInterval = 5,
        file: StaticString = #file,
        line: UInt = #line
    ) -> Bool {
        let predicate = NSPredicate(format: "isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)

        if result != .completed {
            XCTFail("Timed out waiting for element to be hittable: \(element)", file: file, line: line)
            return false
        }
        return true
    }

    /// Waits for element count to match expected value.
    @discardableResult
    func waitForElementCount(
        _ query: XCUIElementQuery,
        count: Int,
        timeout: TimeInterval = 5,
        file: StaticString = #file,
        line: UInt = #line
    ) -> Bool {
        let predicate = NSPredicate(format: "count == \(count)")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: query)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)

        if result != .completed {
            XCTFail(
                "Timed out waiting for element count. Expected: \(count), Actual: \(query.count)",
                file: file,
                line: line
            )
            return false
        }
        return true
    }

    // MARK: - Navigation Helpers

    /// Navigates to a sidebar item by label.
    func navigateToSidebarItem(_ label: String) {
        let sidebarItem = app.outlineRows.staticTexts[label].firstMatch
        if waitForHittable(sidebarItem) {
            sidebarItem.click()
        }
    }

    /// Navigates to Home via sidebar.
    func navigateToHome() {
        navigateToSidebarItem("Home")
    }

    /// Navigates to Search via sidebar.
    func navigateToSearch() {
        navigateToSidebarItem("Search")
    }

    /// Navigates to Explore via sidebar.
    func navigateToExplore() {
        navigateToSidebarItem("Explore")
    }

    /// Navigates to Library via sidebar.
    func navigateToLibrary() {
        navigateToSidebarItem("Playlists")
    }

    /// Navigates to Liked Music via sidebar.
    func navigateToLikedMusic() {
        navigateToSidebarItem("Liked Music")
    }
}
