import SwiftUI

/// Explore view displaying new releases, charts, and moods & genres.
@available(macOS 26.0, *)
struct ExploreView: View {
    @State var viewModel: ExploreViewModel
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
            .navigationTitle("Explore")
            .navigationDestination(for: Playlist.self) { playlist in
                PlaylistDetailView(
                    playlist: playlist,
                    viewModel: PlaylistDetailViewModel(
                        playlist: playlist,
                        client: viewModel.client
                    )
                )
            }
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
            Text("Loading explore content...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                ForEach(viewModel.sections) { section in
                    sectionView(section)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

    private func sectionView(_ section: HomeSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.title2)
                .fontWeight(.semibold)

            if section.isChart {
                chartListView(section)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(section.items) { item in
                            itemCard(item)
                        }
                    }
                }
            }
        }
    }

    private func chartListView(_ section: HomeSection) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 16) {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    chartCard(item, rank: index + 1)
                }
            }
        }
    }

    private func chartCard(_ item: HomeSectionItem, rank: Int) -> some View {
        Button {
            playItem(item)
        } label: {
            ZStack(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    CachedAsyncImage(url: item.thumbnailURL?.highQualityThumbnailURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(.quaternary)
                            .overlay {
                                Image(systemName: "music.note")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                            }
                    }
                    .frame(width: 160, height: 160)
                    .clipShape(.rect(cornerRadius: 8))

                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(width: 160, alignment: .leading)

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: 160, alignment: .leading)
                    }
                }

                Text("\(rank)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                    .padding(.leading, 8)
                    .padding(.bottom, 60)
            }
        }
        .buttonStyle(.plain)
    }

    private func itemCard(_ item: HomeSectionItem) -> some View {
        Button {
            playItem(item)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                CachedAsyncImage(url: item.thumbnailURL?.highQualityThumbnailURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                }
                .frame(width: 160, height: 160)
                .clipShape(.rect(cornerRadius: 8))

                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: 160, alignment: .leading)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 160, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("Unable to load content")
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

    // MARK: - Actions

    private func playItem(_ item: HomeSectionItem) {
        switch item {
        case let .song(song):
            Task {
                await playerService.play(videoId: song.videoId)
            }
        case let .playlist(playlist):
            navigationPath.append(playlist)
        case let .album(album):
            let playlist = Playlist(
                id: album.id,
                title: album.title,
                description: nil,
                thumbnailURL: album.thumbnailURL,
                trackCount: album.trackCount,
                author: album.artistsDisplay
            )
            navigationPath.append(playlist)
        case let .artist(artist):
            navigationPath.append(artist)
        }
    }
}

#Preview {
    let authService = AuthService()
    let client = YTMusicClient(authService: authService, webKitManager: .shared)
    ExploreView(viewModel: ExploreViewModel(client: client))
        .environment(PlayerService())
}
