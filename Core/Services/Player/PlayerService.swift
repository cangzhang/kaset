import Foundation
import Observation
import os

// MARK: - Safe Array Subscript

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - PlayerService

/// Controls music playback via a hidden WKWebView.
@MainActor
@Observable
final class PlayerService: NSObject {
    /// Current playback state.
    enum PlaybackState: Equatable, Sendable {
        case idle
        case loading
        case playing
        case paused
        case buffering
        case ended
        case error(String)

        var isPlaying: Bool {
            self == .playing
        }
    }

    /// Repeat mode for playback.
    enum RepeatMode: Sendable {
        case off
        case all
        case one
    }

    // MARK: - Observable State

    /// Current playback state.
    private(set) var state: PlaybackState = .idle

    /// Currently playing track.
    private(set) var currentTrack: Song?

    /// Whether playback is active.
    var isPlaying: Bool { state.isPlaying }

    /// Current playback position in seconds.
    private(set) var progress: TimeInterval = 0

    /// Total duration of current track in seconds.
    private(set) var duration: TimeInterval = 0

    /// Current volume (0.0 - 1.0).
    private(set) var volume: Double = 1.0

    /// Whether shuffle mode is enabled.
    private(set) var shuffleEnabled: Bool = false

    /// Current repeat mode.
    private(set) var repeatMode: RepeatMode = .off

    /// Playback queue.
    private(set) var queue: [Song] = []

    /// Index of current track in queue.
    private(set) var currentIndex: Int = 0

    /// Whether the mini player should be shown (user needs to interact to start playback).
    var showMiniPlayer: Bool = false

    /// The video ID that needs to be played in the mini player.
    private(set) var pendingPlayVideoId: String?

    // MARK: - Private Properties

    private let logger = DiagnosticsLogger.player

    // MARK: - Initialization

    override init() {
        super.init()
    }

    // MARK: - Public Methods

    /// Plays a track by video ID.
    func play(videoId: String) async {
        logger.info("Playing video: \(videoId)")
        state = .loading

        // Create a minimal Song object for now
        currentTrack = Song(
            id: videoId,
            title: "Loading...",
            artists: [],
            album: nil,
            duration: nil,
            thumbnailURL: nil,
            videoId: videoId
        )

        // Show the mini player for user interaction
        pendingPlayVideoId = videoId
        showMiniPlayer = true
        logger.info("Showing mini player for user to start playback")
    }

    /// Plays a song.
    func play(song: Song) async {
        logger.info("Playing song: \(song.title)")
        state = .loading
        currentTrack = song

        // Show the mini player for user interaction
        pendingPlayVideoId = song.videoId
        showMiniPlayer = true
        logger.info("Showing mini player for user to start playback")
    }

    /// Called when the mini player confirms playback has started.
    func confirmPlaybackStarted() {
        showMiniPlayer = false
        state = .playing
        logger.info("Playback confirmed started")
    }

    /// Called when the mini player is dismissed.
    func miniPlayerDismissed() {
        showMiniPlayer = false
        if state == .loading {
            state = .idle
        }
    }

    /// Updates playback state from the persistent WebView observer.
    func updatePlaybackState(isPlaying: Bool, progress: Double, duration: Double) {
        self.progress = progress
        self.duration = duration
        if isPlaying {
            state = .playing
        } else if state == .playing {
            state = .paused
        }
    }

    /// Updates track metadata when track changes (e.g., via next/previous).
    func updateTrackMetadata(title: String, artist: String, thumbnailUrl: String) {
        logger.debug("Track metadata updated: \(title) - \(artist)")

        let thumbnailURL = URL(string: thumbnailUrl)
        let artistObj = Artist(id: "unknown", name: artist)

        // Preserve videoId if we have it
        let videoId = currentTrack?.videoId ?? pendingPlayVideoId ?? "unknown"

        currentTrack = Song(
            id: videoId,
            title: title,
            artists: [artistObj],
            album: nil,
            duration: duration > 0 ? duration : nil,
            thumbnailURL: thumbnailURL,
            videoId: videoId
        )
    }

    /// Toggles play/pause.
    func playPause() async {
        logger.debug("Toggle play/pause")

        // Use singleton WebView if we have a pending video
        if pendingPlayVideoId != nil {
            SingletonPlayerWebView.shared.playPause()
        } else if isPlaying {
            await pause()
        } else {
            await resume()
        }
    }

    /// Pauses playback.
    func pause() async {
        logger.debug("Pausing playback")
        if pendingPlayVideoId != nil {
            SingletonPlayerWebView.shared.pause()
        } else {
            await evaluatePlayerCommand("pause")
        }
    }

    /// Resumes playback.
    func resume() async {
        logger.debug("Resuming playback")
        if pendingPlayVideoId != nil {
            SingletonPlayerWebView.shared.play()
        } else {
            await evaluatePlayerCommand("play")
        }
    }

    /// Skips to next track.
    func next() async {
        logger.debug("Skipping to next track")

        // Prioritize local queue if we have one
        if !queue.isEmpty {
            // Handle repeat one mode - replay current track
            if repeatMode == .one {
                await seek(to: 0)
                await resume()
                return
            }

            // Handle shuffle mode - pick random track
            if shuffleEnabled {
                let randomIndex = Int.random(in: 0 ..< queue.count)
                currentIndex = randomIndex
                if let nextSong = queue[safe: currentIndex] {
                    await play(song: nextSong)
                }
                return
            }

            // Normal next behavior
            if currentIndex < queue.count - 1 {
                currentIndex += 1
                if let nextSong = queue[safe: currentIndex] {
                    await play(song: nextSong)
                }
            } else if repeatMode == .all {
                // Loop back to start if repeat all is enabled
                currentIndex = 0
                if let firstSong = queue.first {
                    await play(song: firstSong)
                }
            }
            // At end of queue with repeat off, don't do anything
            return
        }

        // Fall back to YouTube's next if no local queue
        if pendingPlayVideoId != nil {
            SingletonPlayerWebView.shared.next()
        }
    }

    /// Goes to previous track.
    func previous() async {
        logger.debug("Going to previous track")

        // Prioritize local queue if we have one
        if !queue.isEmpty {
            if progress > 3 {
                // Restart current track
                if pendingPlayVideoId != nil {
                    SingletonPlayerWebView.shared.seek(to: 0)
                } else {
                    await seek(to: 0)
                }
            } else if currentIndex > 0 {
                currentIndex -= 1
                if let prevSong = queue[safe: currentIndex] {
                    await play(song: prevSong)
                }
            } else {
                // At start of queue, just restart current track
                if pendingPlayVideoId != nil {
                    SingletonPlayerWebView.shared.seek(to: 0)
                } else {
                    await seek(to: 0)
                }
            }
            return
        }

        // Fall back to YouTube's previous if no local queue
        if pendingPlayVideoId != nil {
            if progress > 3 {
                SingletonPlayerWebView.shared.seek(to: 0)
            } else {
                SingletonPlayerWebView.shared.previous()
            }
        } else if progress > 3 {
            await seek(to: 0)
        }
    }

    /// Seeks to a specific time.
    func seek(to time: TimeInterval) async {
        logger.debug("Seeking to \(time)")
        if pendingPlayVideoId != nil {
            SingletonPlayerWebView.shared.seek(to: time)
            progress = time
        } else {
            await evaluatePlayerCommand("seekTo(\(time), true)")
        }
    }

    /// Sets the volume.
    func setVolume(_ value: Double) async {
        let clampedValue = max(0, min(1, value))
        logger.debug("Setting volume to \(clampedValue)")
        volume = clampedValue
        if pendingPlayVideoId != nil {
            SingletonPlayerWebView.shared.setVolume(clampedValue)
        } else {
            await evaluatePlayerCommand("setVolume(\(Int(clampedValue * 100)))")
        }
    }

    /// Toggles shuffle mode.
    func toggleShuffle() {
        shuffleEnabled.toggle()
        logger.info("Shuffle mode: \(self.shuffleEnabled ? "enabled" : "disabled")")
    }

    /// Cycles through repeat modes: off -> all -> one -> off.
    func cycleRepeatMode() {
        switch repeatMode {
        case .off:
            repeatMode = .all
        case .all:
            repeatMode = .one
        case .one:
            repeatMode = .off
        }
        logger.info("Repeat mode: \(String(describing: self.repeatMode))")
    }

    /// Stops playback and clears state.
    func stop() async {
        logger.debug("Stopping playback")
        await evaluatePlayerCommand("pauseVideo()")
        state = .idle
        currentTrack = nil
        progress = 0
        duration = 0
    }

    /// Plays a queue of songs starting at the specified index.
    func playQueue(_ songs: [Song], startingAt index: Int = 0) async {
        guard !songs.isEmpty else { return }
        let safeIndex = max(0, min(index, songs.count - 1))
        queue = songs
        currentIndex = safeIndex
        if let song = songs[safe: safeIndex] {
            await play(song: song)
        }
    }

    // MARK: - Private Methods

    /// Legacy method for evaluating player commands - now delegates to SingletonPlayerWebView.
    private func evaluatePlayerCommand(_ command: String) async {
        // Commands are now routed through SingletonPlayerWebView
        switch command {
        case "pause", "pauseVideo()":
            SingletonPlayerWebView.shared.pause()
        case "play", "playVideo()":
            SingletonPlayerWebView.shared.play()
        default:
            if command.hasPrefix("seekTo(") {
                let timeStr = command.dropFirst(7).prefix(while: { $0 != "," && $0 != ")" })
                if let time = Double(timeStr) {
                    SingletonPlayerWebView.shared.seek(to: time)
                }
            } else if command.hasPrefix("setVolume(") {
                let volStr = command.dropFirst(10).dropLast()
                if let vol = Int(volStr) {
                    SingletonPlayerWebView.shared.setVolume(Double(vol) / 100.0)
                }
            }
        }
    }
}
