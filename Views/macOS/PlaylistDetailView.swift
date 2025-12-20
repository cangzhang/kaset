import SwiftUI

/// Detail view for a playlist showing its tracks.
@available(macOS 26.0, *)
struct PlaylistDetailView: View {
    let playlist: Playlist
    @State var viewModel: PlaylistDetailViewModel
    @Environment(PlayerService.self) private var playerService

    var body: some View {
        Group {
            switch viewModel.loadingState {
            case .idle, .loading:
                loadingView
            case .loaded:
                if let detail = viewModel.playlistDetail {
                    contentView(detail)
                } else {
                    errorView(message: "Playlist not found")
                }
            case let .error(message):
                errorView(message: message)
            }
        }
        .navigationTitle(playlist.title)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PlayerBar()
        }
        .task {
            if viewModel.loadingState == .idle {
                await viewModel.load()
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading playlist...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func contentView(_ detail: PlaylistDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                headerView(detail)

                Divider()

                // Tracks
                tracksView(detail.tracks, isAlbum: detail.isAlbum)
            }
            .padding(24)
        }
    }

    private func headerView(_ detail: PlaylistDetail) -> some View {
        HStack(alignment: .top, spacing: 20) {
            // Thumbnail
            CachedAsyncImage(url: detail.thumbnailURL?.highQualityThumbnailURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: 180, height: 180)
            .clipShape(.rect(cornerRadius: 8))

            // Info
            VStack(alignment: .leading, spacing: 8) {
                Text(detail.isAlbum ? "Album" : "Playlist")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(detail.title)
                    .font(.title)
                    .fontWeight(.bold)

                if let author = detail.author {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 16) {
                    // Play all button
                    Button {
                        playAll(detail.tracks)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(detail.tracks.isEmpty)

                    // Track count
                    Text("\(detail.tracks.count) songs")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let duration = detail.duration {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(duration)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tracksView(_ tracks: [Song], isAlbum: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                trackRow(track, index: index, tracks: tracks, isAlbum: isAlbum)

                if index < tracks.count - 1 {
                    Divider()
                        // For albums: 28 (index) + 12 (spacing)
                        // For playlists: 28 (index) + 12 (spacing) + 40 (thumbnail) + 16 (spacing)
                        .padding(.leading, isAlbum ? 40 : 96)
                }
            }
        }
    }

    private func trackRow(_ track: Song, index: Int, tracks: [Song], isAlbum: Bool) -> some View {
        Button {
            playTrackInQueue(tracks: tracks, startingAt: index)
        } label: {
            HStack(spacing: 12) {
                // Index - use monospaced digits for alignment (display is 1-based)
                Text("\(index + 1)")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)

                // Thumbnail - only show for playlists (different album art per track)
                // Albums share the same artwork, so we hide per-track thumbnails
                if !isAlbum {
                    CachedAsyncImage(url: track.thumbnailURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(.quaternary)
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(.rect(cornerRadius: 4))
                }

                // Title and artist
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(track.artistsDisplay)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Duration
                Text(track.durationDisplay)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 45, alignment: .trailing)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("Unable to load playlist")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Try Again") {
                Task {
                    await viewModel.load()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func playTrackInQueue(tracks: [Song], startingAt index: Int) {
        Task {
            await playerService.playQueue(tracks, startingAt: index)
        }
    }

    private func playAll(_ tracks: [Song]) {
        guard !tracks.isEmpty else { return }
        Task {
            await playerService.playQueue(tracks, startingAt: 0)
        }
    }
}

#Preview {
    let playlist = Playlist(
        id: "test",
        title: "Test Playlist",
        description: nil,
        thumbnailURL: nil,
        trackCount: 10,
        author: "Test Author"
    )
    let authService = AuthService()
    let client = YTMusicClient(authService: authService, webKitManager: .shared)
    PlaylistDetailView(
        playlist: playlist,
        viewModel: PlaylistDetailViewModel(
            playlist: playlist,
            client: client
        )
    )
    .environment(PlayerService())
}
