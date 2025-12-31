#if canImport(FoundationModels)
    import FoundationModels
#endif
import SwiftUI

// MARK: - PlaylistDetailView

/// Detail view for a playlist showing its tracks.
@available(macOS 15.0, *)
struct PlaylistDetailView: View {
    let playlist: Playlist
    @State var viewModel: PlaylistDetailViewModel
    @Environment(PlayerService.self) private var playerService
    @Environment(FavoritesManager.self) private var favoritesManager
    @Environment(SongLikeStatusManager.self) private var likeStatusManager

    /// Tracks whether this playlist has been added to library in this session.
    @State private var isAddedToLibrary: Bool = false

    /// Whether the refine playlist sheet is visible (macOS 26+ only).
    @State private var showRefineSheet: Bool = false

    /// Computed property to check if playlist is in library.
    private var isInLibrary: Bool {
        LibraryViewModel.shared?.isInLibrary(playlistId: self.playlist.id) ?? false
    }

    init(playlist: Playlist, viewModel: PlaylistDetailViewModel) {
        self.playlist = playlist
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            switch self.viewModel.loadingState {
            case .idle, .loading:
                LoadingView("Loading playlist...")
            case .loaded, .loadingMore:
                if let detail = viewModel.playlistDetail {
                    self.contentView(detail)
                } else {
                    ErrorView(title: "Unable to load playlist", message: "Playlist not found") {
                        Task { await self.viewModel.load() }
                    }
                }
            case let .error(error):
                ErrorView(error: error) {
                    Task { await self.viewModel.load() }
                }
            }
        }
        .accentBackground(from: self.viewModel.playlistDetail?.thumbnailURL?.highQualityThumbnailURL)
        .navigationTitle(self.playlist.title)
        .toolbarBackgroundVisibility(.hidden, for: .automatic)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if case .error = self.viewModel.loadingState {} else {
                PlayerBar()
            }
        }
        .task {
            if self.viewModel.loadingState == .idle {
                await self.viewModel.load()
            }
        }
        .refreshable {
            await self.viewModel.refresh()
        }
        #if canImport(FoundationModels)
            .sheet(isPresented: self.$showRefineSheet) {
                if #available(macOS 26.0, *) {
                    if let detail = viewModel.playlistDetail {
                        RefinePlaylistSheet(tracks: detail.tracks)
                    }
                }
            }
        #endif
    }

    // MARK: - Views

    private func contentView(_ detail: PlaylistDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                self.headerView(detail)

                Divider()

                // Tracks
                self.tracksView(detail.tracks, isAlbum: detail.isAlbum)
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
            .fadeIn(duration: 0.3)

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
                        self.playAll(detail.tracks)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(detail.tracks.isEmpty)

                    // Add/Remove Library button
                    let currentlyInLibrary = self.isInLibrary || self.isAddedToLibrary
                    Button {
                        self.toggleLibrary()
                    } label: {
                        Label(
                            currentlyInLibrary ? "Added to Library" : "Add to Library",
                            systemImage: currentlyInLibrary ? "checkmark.circle.fill" : "plus.circle"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    // Refine Playlist button (AI-powered, macOS 26+ only)
                    if !detail.isAlbum {
                        Button {
                            self.showRefineSheet = true
                        } label: {
                            Label("Refine", systemImage: "sparkles")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .requiresIntelligence()
                    }

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
        LazyVStack(spacing: 0) {
            ForEach(tracks.indices, id: \.self) { index in
                let track = tracks[index]
                self.trackRow(track, index: index, tracks: tracks, isAlbum: isAlbum)

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
            self.playTrackInQueue(tracks: tracks, startingAt: index)
        } label: {
            HStack(spacing: 12) {
                // Now playing indicator or index
                Group {
                    if self.playerService.currentTrack?.videoId == track.videoId {
                        NowPlayingIndicator(isPlaying: self.playerService.isPlaying, size: 14)
                    } else {
                        Text("\(index + 1)")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
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
                        .foregroundStyle(self.playerService.currentTrack?.videoId == track.videoId ? .red : .primary)
                        .lineLimit(1)

                    Text(track.artistsDisplay)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Duration
                Text(track.durationDisplay)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 45, alignment: .trailing)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.interactiveRow(cornerRadius: 6))
        .staggeredAppearance(index: min(index, 10))
        .contextMenu {
            Button {
                self.playTrackInQueue(tracks: tracks, startingAt: index)
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            Divider()

            FavoritesContextMenu.menuItem(for: track, manager: self.favoritesManager)

            Divider()

            LikeDislikeContextMenu(song: track, likeStatusManager: self.likeStatusManager)

            Divider()

            Button {
                SongActionsHelper.addToLibrary(track, playerService: self.playerService)
            } label: {
                Label("Add to Library", systemImage: "plus.circle")
            }

            Divider()

            ShareContextMenu.menuItem(for: track)

            Divider()

            // Go to Artist - show first artist with valid ID
            if let artist = track.artists.first(where: { !$0.id.isEmpty && $0.id != UUID().uuidString }) {
                NavigationLink(value: artist) {
                    Label("Go to Artist", systemImage: "person")
                }
            }

            // Go to Album - show if album has valid browse ID
            if let album = track.album, album.hasNavigableId {
                let playlist = Playlist(
                    id: album.id,
                    title: album.title,
                    description: nil,
                    thumbnailURL: album.thumbnailURL ?? track.thumbnailURL,
                    trackCount: album.trackCount,
                    author: album.artistsDisplay
                )
                NavigationLink(value: playlist) {
                    Label("Go to Album", systemImage: "square.stack")
                }
            }
        }
    }

    // MARK: - Actions

    private func playTrackInQueue(tracks: [Song], startingAt index: Int) {
        Task {
            await self.playerService.playQueue(tracks, startingAt: index)
        }
    }

    private func playAll(_ tracks: [Song]) {
        guard !tracks.isEmpty else { return }
        Task {
            await self.playerService.playQueue(tracks, startingAt: 0)
        }
    }

    private func toggleLibrary() {
        let currentlyInLibrary = self.isInLibrary || self.isAddedToLibrary
        HapticService.success()
        Task {
            if currentlyInLibrary {
                await SongActionsHelper.removePlaylistFromLibrary(self.playlist, client: self.viewModel.client)
                self.isAddedToLibrary = false
            } else {
                await SongActionsHelper.addPlaylistToLibrary(self.playlist, client: self.viewModel.client)
                self.isAddedToLibrary = true
            }
        }
    }
}

// MARK: - RefinePlaylistSheet (macOS 26+ only)

#if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private struct RefinePlaylistSheet: View {
        let tracks: [Song]

        @Environment(\.dismiss) private var dismiss

        @State private var promptText: String = ""
        @State private var isProcessing: Bool = false
        @State private var playlistChanges: PlaylistChanges?
        @State private var partialChanges: PlaylistChanges.PartiallyGenerated?
        @State private var errorMessage: String?

        private let logger = DiagnosticsLogger.ai

        var body: some View {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Refine Playlist")
                        .font(.headline)
                    Spacer()
                    Button {
                        self.dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding()

                Divider()

                if let changes = playlistChanges {
                    // Show results
                    self.changesView(changes)
                } else if self.isProcessing, let partial = partialChanges {
                    // Show streaming results
                    self.streamingChangesView(partial)
                } else if let error = errorMessage {
                    // Show error
                    self.errorView(error)
                } else {
                    // Show input
                    self.inputView
                }
            }
            .frame(width: 500, height: 400)
        }

        private var inputView: some View {
            VStack(spacing: 16) {
                Text("Describe what you'd like to change about this playlist")
                    .foregroundStyle(.secondary)

                TextField("e.g., remove duplicates, sort by energy...", text: self.$promptText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(self.isProcessing)

                // Suggestions
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        self.suggestionChip("Remove duplicates")
                        self.suggestionChip("Sort by energy")
                        self.suggestionChip("Remove explicit songs")
                        self.suggestionChip("Keep only upbeat songs")
                    }
                }

                Spacer()

                HStack {
                    Button("Cancel") {
                        self.dismiss()
                    }
                    .keyboardShortcut(.escape)

                    Spacer()

                    Button("Refine") {
                        Task {
                            await self.refinePlaylist()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(self.promptText.isEmpty || self.isProcessing)
                }
            }
            .padding()
        }

        private func errorView(_ error: String) -> some View {
            VStack(spacing: 16) {
                Spacer()

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)

                Text(error)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack {
                    Button("Try Again") {
                        self.errorMessage = nil
                    }

                    Spacer()

                    Button("Cancel") {
                        self.dismiss()
                    }
                    .keyboardShortcut(.escape)
                }
            }
            .padding()
        }

        private func streamingChangesView(_ partial: PlaylistChanges.PartiallyGenerated) -> some View {
            VStack(spacing: 16) {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyzing playlist...")
                        .foregroundStyle(.secondary)
                }

                if let reasoning = partial.reasoning {
                    Text(reasoning)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let removals = partial.removals, !removals.isEmpty {
                    Text("Found \(removals.count) songs to remove...")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .padding()
        }

        private func changesView(_ changes: PlaylistChanges) -> some View {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Reasoning
                        Text(changes.reasoning)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)

                        // Removals
                        if !changes.removals.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Songs to Remove (\(changes.removals.count))")
                                    .font(.headline)
                                    .padding(.horizontal)

                                ForEach(changes.removals, id: \.self) { videoId in
                                    HStack {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.red)
                                        // Find the track info from our tracks list
                                        if let track = self.tracks.first(where: { $0.videoId == videoId }) {
                                            VStack(alignment: .leading) {
                                                Text(track.title)
                                                    .lineLimit(1)
                                                Text(track.artistsDisplay)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        } else {
                                            Text(videoId)
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }

                        if changes.removals.isEmpty, changes.reorderedIds == nil {
                            Text("No changes suggested. The playlist looks good!")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical)
                }

                Divider()

                // Actions
                HStack {
                    Button("Try Again") {
                        self.playlistChanges = nil
                        self.errorMessage = nil
                    }

                    Spacer()

                    Button("Cancel") {
                        self.dismiss()
                    }
                    .keyboardShortcut(.escape)

                    Button("Apply Changes") {
                        // Playlist modification via API not yet implemented
                        self.dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(changes.removals.isEmpty && changes.reorderedIds == nil)
                }
                .padding()
            }
        }

        private func suggestionChip(_ text: String) -> some View {
            Button {
                self.promptText = text
            } label: {
                Text(text)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }

        private func refinePlaylist() async {
            self.isProcessing = true
            self.errorMessage = nil
            self.playlistChanges = nil
            self.partialChanges = nil

            self.logger.info("Refining playlist with prompt: \(self.promptText)")

            let instructions = """
            You are a music playlist curator. Analyze songs and suggest changes based on the request.

            IMPORTANT RULES:
            - A "duplicate" means the EXACT same video ID appears twice. Different versions/covers
              of a song by different artists are NOT duplicates.
            - "Last Christmas" by Wham! and "Last Christmas" by Jimmy Eat World are DIFFERENT songs.
            - Only suggest removing tracks that truly don't fit the user's criteria.
            - When in doubt, keep the song.
            """

            guard let session = FoundationModelsService.shared.createAnalysisSession(instructions: instructions) else {
                self.errorMessage = "Apple Intelligence is not available"
                self.isProcessing = false
                return
            }

            // Build track list - limit to 25 to reduce content filter issues
            let trackLimit = min(self.tracks.count, 25)
            let trackList = self.tracks.prefix(trackLimit).enumerated().map { index, track in
                let safeTitle = track.title.prefix(50)
                let safeArtist = track.artistsDisplay.prefix(30)
                return "\(index + 1). \(safeTitle) - \(safeArtist) [id:\(track.videoId)]"
            }.joined(separator: "\n")

            let userPrompt = """
            Playlist (\(self.tracks.count) songs, showing \(trackLimit)):

            \(trackList)

            Request: \(self.promptText)
            """

            do {
                let stream = session.streamResponse(to: userPrompt, generating: PlaylistChanges.self)

                for try await snapshot in stream {
                    self.partialChanges = snapshot.content
                }

                if let final = self.partialChanges,
                   let removals = final.removals,
                   let reasoning = final.reasoning
                {
                    self.playlistChanges = PlaylistChanges(
                        removals: removals,
                        reorderedIds: final.reorderedIds,
                        reasoning: reasoning
                    )
                    self.logger.info("Got playlist changes: \(removals.count) removals")
                }
            } catch {
                if let message = AIErrorHandler.handleAndMessage(error, context: "playlist refinement") {
                    self.errorMessage = message
                }
            }

            self.partialChanges = nil
            self.isProcessing = false
        }
    }
#endif

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
