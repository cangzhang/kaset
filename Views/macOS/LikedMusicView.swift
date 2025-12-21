import SwiftUI

/// View displaying the user's liked songs.
@available(macOS 26.0, *)
struct LikedMusicView: View {
    @State var viewModel: LikedMusicViewModel
    @Environment(PlayerService.self) private var playerService

    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                switch viewModel.loadingState {
                case .idle, .loading:
                    loadingView
                case .loaded:
                    contentView
                case let .error(message):
                    errorView(message: message)
                }
            }
            .navigationTitle("Liked Music")
            .navigationDestination(for: Artist.self) { artist in
                ArtistDetailView(
                    artist: artist,
                    viewModel: ArtistDetailViewModel(
                        artist: artist,
                        client: viewModel.client
                    )
                )
            }
            .navigationDestination(for: TopSongsDestination.self) { destination in
                TopSongsView(viewModel: TopSongsViewModel(
                    destination: destination,
                    client: viewModel.client
                ))
            }
        }
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
            Text("Loading liked songs...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Header with play all button
                headerView
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)

                // Songs list
                if viewModel.songs.isEmpty {
                    emptyStateView
                } else {
                    ForEach(Array(viewModel.songs.enumerated()), id: \.element.id) { index, song in
                        songRow(song, index: index)
                        if index < viewModel.songs.count - 1 {
                            Divider()
                                .padding(.leading, 72)
                        }
                    }
                }
            }
            .padding(.vertical, 20)
        }
    }

    private var headerView: some View {
        HStack(spacing: 16) {
            // Liked music icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [.red, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: "heart.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Liked Music")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("\(viewModel.songs.count) songs")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Play all button
            if !viewModel.songs.isEmpty {
                Button {
                    Task {
                        await playerService.playQueue(viewModel.songs, startingAt: 0)
                    }
                } label: {
                    Label("Play All", systemImage: "play.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                // Shuffle button
                Button {
                    Task {
                        let shuffled = viewModel.songs.shuffled()
                        await playerService.playQueue(shuffled, startingAt: 0)
                    }
                } label: {
                    Image(systemName: "shuffle")
                        .font(.headline)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No liked songs yet")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Songs you like will appear here")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func songRow(_ song: Song, index: Int) -> some View {
        Button {
            Task {
                await playerService.playQueue(viewModel.songs, startingAt: index)
            }
        } label: {
            HStack(spacing: 12) {
                // Thumbnail
                CachedAsyncImage(url: song.thumbnailURL?.highQualityThumbnailURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "music.note")
                                .foregroundStyle(.secondary)
                        }
                }
                .frame(width: 48, height: 48)
                .clipShape(.rect(cornerRadius: 6))

                // Song info
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.system(size: 14))
                        .lineLimit(1)

                    Text(song.artistsDisplay)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Duration
                if let duration = song.duration {
                    Text(formatDuration(duration))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                // Play indicator
                Image(systemName: "play.circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                Task { await playerService.play(song: song) }
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            Divider()

            Button {
                likeSong(song)
            } label: {
                Label("Unlike", systemImage: "heart.slash")
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func likeSong(_ song: Song) {
        Task {
            await playerService.play(song: song)
            try? await Task.sleep(for: .milliseconds(100))
            playerService.likeCurrentTrack()
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("Unable to load liked songs")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                Task {
                    await viewModel.refresh()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    let authService = AuthService()
    let client = YTMusicClient(authService: authService, webKitManager: .shared)
    LikedMusicView(viewModel: LikedMusicViewModel(client: client))
        .environment(PlayerService())
}
