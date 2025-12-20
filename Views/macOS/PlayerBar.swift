import SwiftUI

/// Player bar shown at the bottom of the content area, styled like Apple Music with Liquid Glass.
@available(macOS 26.0, *)
struct PlayerBar: View {
    @Environment(PlayerService.self) private var playerService
    @Environment(WebKitManager.self) private var webKitManager

    @State private var isHovering = false

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                // Left section: Playback controls
                playbackControls

                Spacer()

                // Center section: Track info OR seek bar (on hover)
                centerSection

                Spacer()

                // Right section: Volume control
                volumeControl
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(height: 52)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    // MARK: - Center Section (track info blurs, seek bar appears on hover)

    private var centerSection: some View {
        ZStack {
            // Track info (blurred when hovering)
            trackInfoView
                .blur(radius: isHovering ? 8 : 0)
                .opacity(isHovering ? 0 : 1)

            // Seek bar (shown when hovering)
            if isHovering {
                seekBarView
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: 400)
    }

    // MARK: - Track Info View

    private var trackInfoView: some View {
        HStack(spacing: 10) {
            // Thumbnail
            CachedAsyncImage(url: playerService.currentTrack?.thumbnailURL?.highQualityThumbnailURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Track info
            if let track = playerService.currentTrack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    Text(track.artistsDisplay.isEmpty ? "Unknown Artist" : track.artistsDisplay)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 200, alignment: .leading)
            }
        }
    }

    // MARK: - Seek Bar View (replaces track info on hover)

    private var seekBarView: some View {
        HStack(spacing: 10) {
            // Elapsed time
            Text(formatTime(playerService.progress))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)

            // Seek slider
            Slider(
                value: Binding(
                    get: { playerService.duration > 0 ? playerService.progress / playerService.duration : 0 },
                    set: { newValue in
                        let seekTime = newValue * playerService.duration
                        Task { await playerService.seek(to: seekTime) }
                    }
                ),
                in: 0 ... 1
            )
            .controlSize(.small)

            // Remaining time
            Text("-\(formatTime(playerService.duration - playerService.progress))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        HStack(spacing: 16) {
            // Shuffle
            Button {
                playerService.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(playerService.shuffleEnabled ? .red : .primary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Shuffle")
            .accessibilityValue(playerService.shuffleEnabled ? "On" : "Off")

            // Previous
            Button {
                Task {
                    await playerService.previous()
                }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous track")

            // Play/Pause
            Button {
                Task {
                    await playerService.playPause()
                }
            } label: {
                Image(systemName: playerService.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playerService.isPlaying ? "Pause" : "Play")

            // Next
            Button {
                Task {
                    await playerService.next()
                }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next track")

            // Repeat
            Button {
                playerService.cycleRepeatMode()
            } label: {
                Image(systemName: repeatIcon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(playerService.repeatMode != .off ? .red : .primary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Repeat")
            .accessibilityValue(repeatAccessibilityValue)
        }
    }

    private var repeatIcon: String {
        switch playerService.repeatMode {
        case .off, .all:
            "repeat"
        case .one:
            "repeat.1"
        }
    }

    private var repeatAccessibilityValue: String {
        switch playerService.repeatMode {
        case .off:
            "Off"
        case .all:
            "All"
        case .one:
            "One"
        }
    }

    // MARK: - Volume Control

    private var volumeControl: some View {
        HStack(spacing: 8) {
            // Like/Dislike/Library actions
            actionButtons

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            Image(systemName: volumeIcon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary.opacity(0.6))
                .frame(width: 16)

            Slider(
                value: Binding(
                    get: { playerService.volume },
                    set: { newValue in
                        Task {
                            await playerService.setVolume(newValue)
                        }
                    }
                ),
                in: 0 ... 1
            )
            .frame(width: 80)
            .controlSize(.small)
        }
    }

// MARK: - Action Buttons (Like/Dislike/Library)

    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Dislike button
            Button {
                playerService.dislikeCurrentTrack()
            } label: {
                Image(systemName: playerService.currentTrackLikeStatus == .dislike
                    ? "hand.thumbsdown.fill"
                    : "hand.thumbsdown")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(playerService.currentTrackLikeStatus == .dislike ? .red : .primary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dislike")
            .accessibilityValue(playerService.currentTrackLikeStatus == .dislike ? "Disliked" : "Not disliked")
            .disabled(playerService.currentTrack == nil)

            // Like button
            Button {
                playerService.likeCurrentTrack()
            } label: {
                Image(systemName: playerService.currentTrackLikeStatus == .like
                    ? "hand.thumbsup.fill"
                    : "hand.thumbsup")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(playerService.currentTrackLikeStatus == .like ? .red : .primary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Like")
            .accessibilityValue(playerService.currentTrackLikeStatus == .like ? "Liked" : "Not liked")
            .disabled(playerService.currentTrack == nil)

            // Add to Library button
            Button {
                playerService.toggleLibraryStatus()
            } label: {
                Image(systemName: playerService.currentTrackInLibrary
                    ? "plus.circle.fill"
                    : "plus.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(playerService.currentTrackInLibrary ? .red : .primary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playerService.currentTrackInLibrary ? "Remove from Library" : "Add to Library")
            .disabled(playerService.currentTrack == nil)
        }
    }

    private var volumeIcon: String {
        if playerService.volume == 0 {
            "speaker.slash.fill"
        } else if playerService.volume < 0.5 {
            "speaker.wave.1.fill"
        } else {
            "speaker.wave.2.fill"
        }
    }
}

@available(macOS 26.0, *)
#Preview {
    PlayerBar()
        .environment(PlayerService())
        .environment(WebKitManager.shared)
        .frame(width: 600)
        .padding()
        .background(.black)
}
