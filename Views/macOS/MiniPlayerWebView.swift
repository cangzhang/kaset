import SwiftUI
import WebKit

// MARK: - MiniPlayerWebView

/// A visible WebView that displays the YouTube Music player.
/// This is required because YouTube Music won't initialize the video player
/// without user interaction - autoplay is blocked in hidden WebViews.
/// Uses SingletonPlayerWebView for the actual WebView instance.
struct MiniPlayerWebView: NSViewRepresentable {
    @Environment(WebKitManager.self) private var webKitManager
    @Environment(PlayerService.self) private var playerService

    /// The video ID to play.
    let videoId: String

    /// Callback for player state changes.
    var onStateChange: ((PlayerState) -> Void)?

    /// Callback for metadata updates (title, artist, duration).
    var onMetadataChange: ((String, String, Double) -> Void)?

    enum PlayerState {
        case loading
        case playing
        case paused
        case ended
        case error(String)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onStateChange: onStateChange, onMetadataChange: onMetadataChange)
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        container.wantsLayer = true

        // Get or create the singleton WebView
        let webView = SingletonPlayerWebView.shared.getWebView(
            webKitManager: webKitManager,
            playerService: playerService
        )

        // Add additional message handler for this view's callbacks
        webView.configuration.userContentController.add(context.coordinator, name: "miniPlayer")

        // Ensure WebView is in this container
        SingletonPlayerWebView.shared.ensureInHierarchy(container: container)

        // Load the video if needed
        SingletonPlayerWebView.shared.loadVideo(videoId: videoId)

        return container
    }

    func updateNSView(_ container: NSView, context _: Context) {
        // Update WebView frame if needed
        SingletonPlayerWebView.shared.ensureInHierarchy(container: container)
    }

    static func dismantleNSView(_: NSView, coordinator _: Coordinator) {
        // WebView is managed by SingletonPlayerWebView.shared - it persists
        // Remove the message handler to avoid duplicate handlers
        SingletonPlayerWebView.shared.webView?.configuration.userContentController.removeScriptMessageHandler(forName: "miniPlayer")
    }

    // MARK: - Observer Script

    /// Script that observes the YouTube Music player bar and sends updates
    private static var observerScript: String {
        """
        (function() {
            'use strict';

            const bridge = window.webkit.messageHandlers.miniPlayer;

            function log(msg) {
                console.log('[MiniPlayer] ' + msg);
            }

            // Wait for the player bar to appear and observe it
            function waitForPlayerBar() {
                const playerBar = document.querySelector('ytmusic-player-bar');
                if (playerBar) {
                    log('Player bar found, setting up observer');
                    setupObserver(playerBar);
                    return;
                }
                setTimeout(waitForPlayerBar, 500);
            }

            function setupObserver(playerBar) {
                const observer = new MutationObserver(function(mutations) {
                    sendUpdate();
                });

                observer.observe(playerBar, {
                    attributes: true,
                    characterData: true,
                    childList: true,
                    subtree: true,
                    attributeOldValue: true,
                    characterDataOldValue: true
                });

                // Send initial update
                sendUpdate();

                // Also send periodic updates
                setInterval(sendUpdate, 1000);
            }

            function sendUpdate() {
                try {
                    const titleEl = document.querySelector('.ytmusic-player-bar.title');
                    const artistEl = document.querySelector('.ytmusic-player-bar.byline');
                    const progressBar = document.querySelector('#progress-bar');
                    const playPauseBtn = document.querySelector('.play-pause-button.ytmusic-player-bar');

                    const title = titleEl ? titleEl.textContent : '';
                    const artist = artistEl ? artistEl.textContent : '';
                    const progress = progressBar ? parseInt(progressBar.getAttribute('value') || '0') : 0;
                    const duration = progressBar ? parseInt(progressBar.getAttribute('aria-valuemax') || '0') : 0;

                    // Check if playing by looking at the button title
                    const isPlaying = playPauseBtn ?
                        playPauseBtn.getAttribute('title') === 'Pause' ||
                        playPauseBtn.getAttribute('aria-label') === 'Pause' : false;

                    bridge.postMessage({
                        type: 'STATE_UPDATE',
                        title: title,
                        artist: artist,
                        progress: progress,
                        duration: duration,
                        isPlaying: isPlaying
                    });
                } catch (e) {
                    log('Error sending update: ' + e);
                }
            }

            // Start waiting
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', waitForPlayerBar);
            } else {
                waitForPlayerBar();
            }
        })();
        """
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onStateChange: ((PlayerState) -> Void)?
        var onMetadataChange: ((String, String, Double) -> Void)?

        init(
            onStateChange: ((PlayerState) -> Void)?,
            onMetadataChange: ((String, String, Double) -> Void)?
        ) {
            self.onStateChange = onStateChange
            self.onMetadataChange = onMetadataChange
        }

        func webView(_: WKWebView, didFinish _: WKNavigation!) {
            // Page loaded
        }

        func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
            onStateChange?(.error(error.localizedDescription))
        }

        func userContentController(
            _: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String
            else { return }

            if type == "STATE_UPDATE" {
                let title = body["title"] as? String ?? ""
                let artist = body["artist"] as? String ?? ""
                let duration = body["duration"] as? Double ?? 0
                let isPlaying = body["isPlaying"] as? Bool ?? false

                if !title.isEmpty {
                    onMetadataChange?(title, artist, duration)
                }

                onStateChange?(isPlaying ? .playing : .paused)
            }
        }
    }
}

// MARK: - CompactPlayToast

/// A compact, unobtrusive toast that appears to let the user start playback.
/// YouTube Music requires a user gesture, so we show this minimal popup.
/// Only shown on first playback; subsequent plays auto-start.
struct CompactPlayToast: View {
    @Environment(WebKitManager.self) private var webKitManager
    @Environment(PlayerService.self) private var playerService

    let videoId: String

    @State private var playbackStarted = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Show the WebView for user to click play
            MiniPlayerWebView(
                videoId: videoId,
                onStateChange: { state in
                    if case .playing = state {
                        if !playbackStarted {
                            playbackStarted = true
                            // Transfer WebView to AppDelegate and dismiss
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(500))
                                playerService.confirmPlaybackStarted()
                            }
                        }
                    }
                }
            )
            .frame(width: 120, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Small dismiss button
            Button {
                playerService.confirmPlaybackStarted()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .shadow(radius: 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .padding(3)
        }
        .frame(width: 120, height: 68)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .opacity(0.95)
        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
    }
}

// MARK: - SingletonPlayerWebView

/// Manages a single WebView instance for the entire app lifetime.
/// This ensures there's only ever ONE WebView playing audio.
@MainActor
final class SingletonPlayerWebView {
    static let shared = SingletonPlayerWebView()

    private(set) var webView: WKWebView?
    var currentVideoId: String?
    private var coordinator: Coordinator?
    private let logger = DiagnosticsLogger.player

    private init() {}

    /// Get or create the singleton WebView.
    func getWebView(
        webKitManager: WebKitManager,
        playerService: PlayerService
    ) -> WKWebView {
        if let existing = webView {
            return existing
        }

        logger.info("Creating singleton WebView")

        // Create coordinator
        coordinator = Coordinator(playerService: playerService)

        let configuration = webKitManager.createWebViewConfiguration()

        // Add script message handler
        configuration.userContentController.add(coordinator!, name: "singletonPlayer")

        // Inject observer script
        let script = WKUserScript(
            source: Self.observerScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(script)

        let newWebView = WKWebView(frame: .zero, configuration: configuration)
        newWebView.navigationDelegate = coordinator
        newWebView.customUserAgent = WebKitManager.userAgent

        #if DEBUG
            newWebView.isInspectable = true
        #endif

        webView = newWebView
        return newWebView
    }

    /// Ensures the WebView is in the given container's view hierarchy.
    func ensureInHierarchy(container: NSView) {
        guard let webView, webView.superview !== container else { return }
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
    }

    /// Load a video, stopping any currently playing audio first.
    func loadVideo(videoId: String) {
        guard let webView else {
            logger.error("loadVideo called but webView is nil")
            return
        }

        let previousVideoId = currentVideoId
        guard videoId != previousVideoId else {
            logger.info("Video \(videoId) already loaded, skipping")
            return
        }

        logger.info("Loading video: \(videoId) (was: \(previousVideoId ?? "none"))")

        // Update currentVideoId immediately to prevent duplicate loads
        currentVideoId = videoId

        // Stop current playback first, then load new video
        let urlToLoad = URL(string: "https://music.youtube.com/watch?v=\(videoId)")!
        webView.evaluateJavaScript("document.querySelector('video')?.pause()") { [weak self] _, _ in
            self?.webView?.load(URLRequest(url: urlToLoad))
        }
    }

    // MARK: - Playback Controls

    /// Toggle play/pause.
    func playPause() {
        guard let webView else { return }
        logger.debug("playPause() called")

        let script = """
            (function() {
                const playBtn = document.querySelector('.play-pause-button.ytmusic-player-bar');
                if (playBtn) { playBtn.click(); return 'clicked'; }
                const video = document.querySelector('video');
                if (video) {
                    if (video.paused) { video.play(); return 'played'; }
                    else { video.pause(); return 'paused'; }
                }
                return 'no-element';
            })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, error in
            if let error {
                self?.logger.error("playPause error: \(error.localizedDescription)")
            } else {
                self?.logger.debug("playPause result: \(String(describing: result))")
            }
        }
    }

    /// Play (resume).
    func play() {
        guard let webView else { return }
        logger.debug("play() called")

        let script = """
            (function() {
                const video = document.querySelector('video');
                if (video && video.paused) { video.play(); return 'played'; }
                return 'already-playing';
            })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// Pause.
    func pause() {
        guard let webView else { return }
        logger.debug("pause() called")

        let script = """
            (function() {
                const video = document.querySelector('video');
                if (video && !video.paused) { video.pause(); return 'paused'; }
                return 'already-paused';
            })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// Skip to next track.
    func next() {
        guard let webView else { return }
        logger.debug("next() called")

        let script = """
            (function() {
                const nextBtn = document.querySelector('.next-button.ytmusic-player-bar');
                if (nextBtn) { nextBtn.click(); return 'clicked'; }
                return 'no-button';
            })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, error in
            if let error {
                self?.logger.error("next error: \(error.localizedDescription)")
            } else {
                self?.logger.debug("next result: \(String(describing: result))")
            }
        }
    }

    /// Go to previous track.
    func previous() {
        guard let webView else { return }
        logger.debug("previous() called")

        let script = """
            (function() {
                const prevBtn = document.querySelector('.previous-button.ytmusic-player-bar');
                if (prevBtn) { prevBtn.click(); return 'clicked'; }
                return 'no-button';
            })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, error in
            if let error {
                self?.logger.error("previous error: \(error.localizedDescription)")
            } else {
                self?.logger.debug("previous result: \(String(describing: result))")
            }
        }
    }

    /// Seek to a specific time in seconds.
    func seek(to time: Double) {
        guard let webView else { return }
        logger.debug("seek(to: \(time)) called")

        let script = """
            (function() {
                const video = document.querySelector('video');
                if (video) { video.currentTime = \(time); return 'seeked'; }
                return 'no-video';
            })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// Set volume (0.0 - 1.0).
    func setVolume(_ volume: Double) {
        guard let webView else { return }
        let clampedVolume = max(0, min(1, volume))
        logger.debug("setVolume(\(clampedVolume)) called")

        let script = """
            (function() {
                const video = document.querySelector('video');
                if (video) { video.volume = \(clampedVolume); return 'set'; }
                return 'no-video';
            })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    // MARK: - Like/Dislike/Library Controls

    /// Click the like (thumbs up) button in the player bar.
    func clickLikeButton() {
        guard let webView else { return }
        logger.debug("clickLikeButton() called")

        let script = """
            (function() {
                // Try the like button in the player bar
                const likeBtn = document.querySelector('ytmusic-like-button-renderer #button-shape-like button, ytmusic-like-button-renderer .like');
                if (likeBtn) { likeBtn.click(); return 'clicked-like'; }

                // Try alternative selector
                const altLikeBtn = document.querySelector('.ytmusic-player-bar ytmusic-like-button-renderer button[aria-label*="like" i]');
                if (altLikeBtn) { altLikeBtn.click(); return 'clicked-alt-like'; }

                return 'no-like-button';
            })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, error in
            if let error {
                self?.logger.error("clickLikeButton error: \(error.localizedDescription)")
            } else {
                self?.logger.debug("clickLikeButton result: \(String(describing: result))")
            }
        }
    }

    /// Click the dislike (thumbs down) button in the player bar.
    func clickDislikeButton() {
        guard let webView else { return }
        logger.debug("clickDislikeButton() called")

        let script = """
            (function() {
                // Try the dislike button in the player bar
                const dislikeBtn = document.querySelector('ytmusic-like-button-renderer #button-shape-dislike button, ytmusic-like-button-renderer .dislike');
                if (dislikeBtn) { dislikeBtn.click(); return 'clicked-dislike'; }

                // Try alternative selector
                const altDislikeBtn = document.querySelector('.ytmusic-player-bar ytmusic-like-button-renderer button[aria-label*="dislike" i]');
                if (altDislikeBtn) { altDislikeBtn.click(); return 'clicked-alt-dislike'; }

                return 'no-dislike-button';
            })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, error in
            if let error {
                self?.logger.error("clickDislikeButton error: \(error.localizedDescription)")
            } else {
                self?.logger.debug("clickDislikeButton result: \(String(describing: result))")
            }
        }
    }

    /// Click the add to library button.
    func clickAddToLibraryButton() {
        guard let webView else { return }
        logger.debug("clickAddToLibraryButton() called")

        let script = """
            (function() {
                // Try the save/library button in the player bar (usually in the menu)
                // First, try the three-dot menu button to open it
                const menuBtn = document.querySelector('ytmusic-player-bar .menu button, ytmusic-player-bar tp-yt-paper-icon-button.dropdown-trigger');
                if (menuBtn) {
                    menuBtn.click();
                    // Wait a moment for menu to open, then click add to library
                    setTimeout(function() {
                        const addToLibrary = document.querySelector('ytmusic-menu-popup-renderer [aria-label*="library" i], ytmusic-menu-popup-renderer tp-yt-paper-item:has(yt-icon[icon*="library"])');
                        if (addToLibrary) {
                            addToLibrary.click();
                            return 'clicked-add-to-library';
                        }
                    }, 200);
                    return 'opened-menu';
                }

                // Try direct add to library button if it exists
                const directBtn = document.querySelector('.ytmusic-player-bar [aria-label*="Add to library" i], .ytmusic-player-bar [aria-label*="Save to library" i]');
                if (directBtn) { directBtn.click(); return 'clicked-direct'; }

                return 'no-library-button';
            })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, error in
            if let error {
                self?.logger.error("clickAddToLibraryButton error: \(error.localizedDescription)")
            } else {
                self?.logger.debug("clickAddToLibraryButton result: \(String(describing: result))")
            }
        }
    }

    // Observer script for playback state
    private static var observerScript: String {
        """
        (function() {
            'use strict';
            const bridge = window.webkit.messageHandlers.singletonPlayer;
            let lastTitle = '';
            let lastArtist = '';

            function waitForPlayerBar() {
                const playerBar = document.querySelector('ytmusic-player-bar');
                if (playerBar) {
                    setupObserver(playerBar);
                    return;
                }
                setTimeout(waitForPlayerBar, 500);
            }

            function setupObserver(playerBar) {
                const observer = new MutationObserver(sendUpdate);
                observer.observe(playerBar, {
                    attributes: true, characterData: true,
                    childList: true, subtree: true
                });
                sendUpdate();
                setInterval(sendUpdate, 1000);
            }

            function sendUpdate() {
                try {
                    const playPauseBtn = document.querySelector('.play-pause-button.ytmusic-player-bar');
                    const isPlaying = playPauseBtn ?
                        (playPauseBtn.getAttribute('title') === 'Pause' ||
                         playPauseBtn.getAttribute('aria-label') === 'Pause') : false;

                    const progressBar = document.querySelector('#progress-bar');

                    // Extract track metadata
                    const titleEl = document.querySelector('.ytmusic-player-bar.title');
                    const artistEl = document.querySelector('.ytmusic-player-bar.byline');
                    const thumbEl = document.querySelector('.ytmusic-player-bar .thumbnail img, ytmusic-player-bar .image');

                    const title = titleEl ? titleEl.textContent.trim() : '';
                    const artist = artistEl ? artistEl.textContent.trim() : '';
                    let thumbnailUrl = '';

                    // Get the thumbnail URL from the image element
                    if (thumbEl) {
                        thumbnailUrl = thumbEl.src || thumbEl.getAttribute('src') || '';
                    }

                    // Extract like status from the like button renderer
                    let likeStatus = 'INDIFFERENT';
                    const likeRenderer = document.querySelector('ytmusic-like-button-renderer');
                    if (likeRenderer) {
                        const status = likeRenderer.getAttribute('like-status');
                        if (status === 'LIKE') likeStatus = 'LIKE';
                        else if (status === 'DISLIKE') likeStatus = 'DISLIKE';
                    }

                    // Check if track changed
                    const trackChanged = (title !== lastTitle || artist !== lastArtist) && title !== '';
                    if (trackChanged) {
                        lastTitle = title;
                        lastArtist = artist;
                    }

                    bridge.postMessage({
                        type: 'STATE_UPDATE',
                        isPlaying: isPlaying,
                        progress: progressBar ? parseInt(progressBar.getAttribute('value') || '0') : 0,
                        duration: progressBar ? parseInt(progressBar.getAttribute('aria-valuemax') || '0') : 0,
                        title: title,
                        artist: artist,
                        thumbnailUrl: thumbnailUrl,
                        trackChanged: trackChanged,
                        likeStatus: likeStatus
                    });
                } catch (e) {}
            }

            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', waitForPlayerBar);
            } else {
                waitForPlayerBar();
            }
        })();
        """
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let playerService: PlayerService

        init(playerService: PlayerService) {
            self.playerService = playerService
        }

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String,
                  type == "STATE_UPDATE"
            else { return }

            let isPlaying = body["isPlaying"] as? Bool ?? false
            let progress = body["progress"] as? Int ?? 0
            let duration = body["duration"] as? Int ?? 0
            let title = body["title"] as? String ?? ""
            let artist = body["artist"] as? String ?? ""
            let thumbnailUrl = body["thumbnailUrl"] as? String ?? ""
            let trackChanged = body["trackChanged"] as? Bool ?? false
            let likeStatusString = body["likeStatus"] as? String ?? "INDIFFERENT"

            // Parse like status
            let likeStatus: LikeStatus = switch likeStatusString {
            case "LIKE":
                .like
            case "DISLIKE":
                .dislike
            default:
                .indifferent
            }

            Task { @MainActor in
                self.playerService.updatePlaybackState(
                    isPlaying: isPlaying,
                    progress: Double(progress),
                    duration: Double(duration)
                )

                // Update like status only when track changes (initial state)
                if trackChanged {
                    self.playerService.updateLikeStatus(likeStatus)
                }

                // Update track metadata if track changed
                if trackChanged, !title.isEmpty {
                    self.playerService.updateTrackMetadata(
                        title: title,
                        artist: artist,
                        thumbnailUrl: thumbnailUrl
                    )
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            DiagnosticsLogger.player.info("Singleton WebView finished loading: \(webView.url?.absoluteString ?? "nil")")
        }
    }
}

// MARK: - PersistentPlayerView

/// A SwiftUI view that displays the singleton WebView.
/// The WebView is created once and reused for all playback.
struct PersistentPlayerView: NSViewRepresentable {
    @Environment(WebKitManager.self) private var webKitManager
    @Environment(PlayerService.self) private var playerService

    let videoId: String
    let isExpanded: Bool

    private let logger = DiagnosticsLogger.player

    func makeNSView(context _: Context) -> NSView {
        logger.info("PersistentPlayerView.makeNSView for videoId: \(videoId)")

        let container = NSView(frame: .zero)
        container.wantsLayer = true

        // Get or create the singleton WebView
        let webView = SingletonPlayerWebView.shared.getWebView(
            webKitManager: webKitManager,
            playerService: playerService
        )

        // Remove from any previous superview and add to this container
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)

        // Load the video if needed
        if SingletonPlayerWebView.shared.currentVideoId != videoId {
            let url = URL(string: "https://music.youtube.com/watch?v=\(videoId)")!
            logger.info("Initial load: \(url.absoluteString)")
            webView.load(URLRequest(url: url))
            SingletonPlayerWebView.shared.currentVideoId = videoId
        }

        return container
    }

    func updateNSView(_ container: NSView, context _: Context) {
        logger.info("PersistentPlayerView.updateNSView for videoId: \(videoId)")

        // Ensure WebView is in this container
        let webView = SingletonPlayerWebView.shared.getWebView(
            webKitManager: webKitManager,
            playerService: playerService
        )

        if webView.superview !== container {
            logger.info("Re-parenting WebView to current container")
            webView.removeFromSuperview()
            webView.frame = container.bounds
            webView.autoresizingMask = [.width, .height]
            container.addSubview(webView)
        }

        webView.frame = container.bounds

        // Load new video if changed
        SingletonPlayerWebView.shared.loadVideo(videoId: videoId)
    }
}

// MARK: - MiniPlayerPopup

/// A small popup overlay prompting user to click play.
struct MiniPlayerPopup: View {
    @Environment(WebKitManager.self) private var webKitManager
    @Environment(PlayerService.self) private var playerService

    let videoId: String
    let songTitle: String

    @State private var playbackDetected = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("🎵 \(songTitle)")
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Button {
                    playerService.miniPlayerDismissed()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }

            // Visible mini WebView for user interaction
            MiniPlayerWebView(
                videoId: videoId,
                onStateChange: { state in
                    if case .playing = state {
                        if !playbackDetected {
                            playbackDetected = true
                            // Auto-dismiss after playback starts
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(1))
                                playerService.confirmPlaybackStarted()
                            }
                        }
                    }
                }
            )
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("Click play above to start music")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 350)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 20)
    }
}

// MARK: - MiniPlayerSheet

/// A compact sheet that shows the YouTube Music player for a specific video.
/// Auto-dismisses once playback starts.
struct MiniPlayerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WebKitManager.self) private var webKitManager
    @Environment(PlayerService.self) private var playerService

    let videoId: String
    let songTitle: String

    @State private var isPlaying = false
    @State private var playbackStarted = false

    var body: some View {
        VStack(spacing: 8) {
            // Compact header
            HStack {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
                Text("Click play to start")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    playerService.miniPlayerDismissed()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Compact WebView - just show the player controls
            MiniPlayerWebView(
                videoId: videoId,
                onStateChange: { state in
                    if case .playing = state {
                        if !playbackStarted {
                            playbackStarted = true
                            // Auto-dismiss after a short delay once playing
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(1500))
                                playerService.confirmPlaybackStarted()
                                dismiss()
                            }
                        }
                        isPlaying = true
                    }
                }
            )
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(8)
        .frame(width: 320, height: 180)
        .background(.ultraThinMaterial)
    }
}

#Preview {
    MiniPlayerSheet(videoId: "dQw4w9WgXcQ", songTitle: "Test Song")
        .environment(WebKitManager.shared)
        .environment(PlayerService())
}
