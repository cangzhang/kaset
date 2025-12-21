import Foundation
import Observation
import os

/// View model for the Home view.
@MainActor
@Observable
final class HomeViewModel {
    /// Current loading state.
    private(set) var loadingState: LoadingState = .idle

    /// Home sections to display.
    private(set) var sections: [HomeSection] = []

    /// Whether more sections are available to load.
    private(set) var hasMoreSections: Bool = true

    /// The API client (exposed for navigation to detail views).
    let client: any YTMusicClientProtocol
    private let logger = DiagnosticsLogger.api

    /// Task for background loading of additional sections.
    private var backgroundLoadTask: Task<Void, Never>?

    /// Number of background continuations loaded.
    private var continuationsLoaded = 0

    /// Maximum continuations to load in background.
    private static let maxContinuations = 4

    init(client: any YTMusicClientProtocol) {
        self.client = client
    }

    /// Loads home content with fast initial load.
    func load() async {
        guard loadingState != .loading else { return }

        loadingState = .loading
        logger.info("Loading home content")

        do {
            let response = try await client.getHome()
            sections = response.sections
            hasMoreSections = client.hasMoreHomeSections
            loadingState = .loaded
            continuationsLoaded = 0
            let sectionCount = sections.count
            logger.info("Home content loaded: \(sectionCount) sections")

            // Start background loading of additional sections
            startBackgroundLoading()
        } catch is CancellationError {
            // Task was cancelled (e.g., user navigated away) — reset to idle so it can retry
            logger.debug("Home load cancelled")
            loadingState = .idle
        } catch {
            logger.error("Failed to load home: \(error.localizedDescription)")
            loadingState = .error(error.localizedDescription)
        }
    }

    /// Loads more sections in the background progressively.
    private func startBackgroundLoading() {
        backgroundLoadTask?.cancel()
        backgroundLoadTask = Task { [weak self] in
            guard let self else { return }

            // Brief delay to let the UI settle
            try? await Task.sleep(for: .milliseconds(300))

            guard !Task.isCancelled else { return }

            await loadMoreSections()
        }
    }

    /// Loads additional sections from continuations progressively.
    private func loadMoreSections() async {
        while hasMoreSections, continuationsLoaded < Self.maxContinuations {
            guard loadingState == .loaded else { break }

            do {
                if let additionalSections = try await client.getHomeContinuation() {
                    sections.append(contentsOf: additionalSections)
                    continuationsLoaded += 1
                    hasMoreSections = client.hasMoreHomeSections
                    let continuationNum = continuationsLoaded
                    logger.info("Background loaded \(additionalSections.count) more sections (continuation \(continuationNum))")
                } else {
                    hasMoreSections = false
                    break
                }
            } catch is CancellationError {
                logger.debug("Background loading cancelled")
                break
            } catch {
                logger.warning("Background section load failed: \(error.localizedDescription)")
                break
            }
        }

        let totalCount = sections.count
        logger.info("Background section loading completed, total sections: \(totalCount)")
    }

    /// Refreshes home content.
    func refresh() async {
        backgroundLoadTask?.cancel()
        sections = []
        hasMoreSections = true
        continuationsLoaded = 0
        await load()
    }
}
