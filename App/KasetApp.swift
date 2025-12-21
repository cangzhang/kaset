import AppKit
import SwiftUI

// MARK: - SearchFocusTriggerKey

/// Environment key for triggering search focus from keyboard shortcut.
struct SearchFocusTriggerKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var searchFocusTrigger: Binding<Bool> {
        get { self[SearchFocusTriggerKey.self] }
        set { self[SearchFocusTriggerKey.self] = newValue }
    }
}

// MARK: - NavigationSelectionKey

/// Environment key for navigation selection.
struct NavigationSelectionKey: EnvironmentKey {
    static let defaultValue: Binding<NavigationItem?> = .constant(nil)
}

extension EnvironmentValues {
    var navigationSelection: Binding<NavigationItem?> {
        get { self[NavigationSelectionKey.self] }
        set { self[NavigationSelectionKey.self] = newValue }
    }
}

// MARK: - KasetApp

/// Main entry point for the Kaset macOS application.
@available(macOS 26.0, *)
@main
struct KasetApp: App {
    /// App delegate for lifecycle management (background playback).
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var authService = AuthService()
    @State private var webKitManager = WebKitManager.shared
    @State private var playerService = PlayerService()
    @State private var ytMusicClient: YTMusicClient?
    @State private var notificationService: NotificationService?

    /// Triggers search field focus when set to true.
    @State private var searchFocusTrigger = false

    /// Current navigation selection for keyboard navigation.
    @State private var navigationSelection: NavigationItem? = .home

    init() {
        let auth = AuthService()
        let webkit = WebKitManager.shared
        let player = PlayerService()

        // Use mock client in UI test mode, real client otherwise
        let realClient = YTMusicClient(authService: auth, webKitManager: webkit)
        let client: YTMusicClientProtocol = if UITestConfig.isUITestMode {
            MockUITestYTMusicClient()
        } else {
            realClient
        }

        // Wire up dependencies
        player.setYTMusicClient(client)

        _authService = State(initialValue: auth)
        _webKitManager = State(initialValue: webkit)
        _playerService = State(initialValue: player)
        _ytMusicClient = State(initialValue: UITestConfig.isUITestMode ? nil : realClient)
        _notificationService = State(initialValue: NotificationService(playerService: player))

        if UITestConfig.isUITestMode {
            DiagnosticsLogger.ui.info("App launched in UI Test mode")
        }
    }

    var body: some Scene {
        WindowGroup {
            // Skip UI during unit tests to prevent window spam
            if UITestConfig.isRunningUnitTests, !UITestConfig.isUITestMode {
                Color.clear
                    .frame(width: 1, height: 1)
            } else {
                MainWindow(navigationSelection: $navigationSelection)
                    .environment(authService)
                    .environment(webKitManager)
                    .environment(playerService)
                    .environment(\.searchFocusTrigger, $searchFocusTrigger)
                    .environment(\.navigationSelection, $navigationSelection)
                    .task {
                        // Check if user is already logged in from previous session
                        await authService.checkLoginStatus()
                    }
            }
        }
        .commands {
            // App commands
            CommandGroup(after: .appInfo) {
                Button("Sign Out") {
                    Task {
                        await authService.signOut()
                    }
                }
                .disabled(authService.state == .loggedOut)
            }

            // Playback commands
            CommandMenu("Playback") {
                // Play/Pause - Space
                Button(playerService.isPlaying ? "Pause" : "Play") {
                    Task {
                        await playerService.playPause()
                    }
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(playerService.currentTrack == nil && playerService.pendingPlayVideoId == nil)

                Divider()

                // Next Track - ⌘→
                Button("Next") {
                    Task {
                        await playerService.next()
                    }
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)

                // Previous Track - ⌘←
                Button("Previous") {
                    Task {
                        await playerService.previous()
                    }
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)

                Divider()

                // Volume Up - ⌘↑
                Button("Volume Up") {
                    Task {
                        await playerService.setVolume(min(1.0, playerService.volume + 0.1))
                    }
                }
                .keyboardShortcut(.upArrow, modifiers: .command)

                // Volume Down - ⌘↓
                Button("Volume Down") {
                    Task {
                        await playerService.setVolume(max(0.0, playerService.volume - 0.1))
                    }
                }
                .keyboardShortcut(.downArrow, modifiers: .command)

                // Mute - ⌘⇧M
                Button(playerService.isMuted ? "Unmute" : "Mute") {
                    Task {
                        await playerService.toggleMute()
                    }
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Divider()

                // Shuffle - ⌘S
                Button(playerService.shuffleEnabled ? "Shuffle Off" : "Shuffle On") {
                    playerService.toggleShuffle()
                }
                .keyboardShortcut("s", modifiers: .command)

                // Repeat - ⌘R
                Button(repeatModeLabel) {
                    playerService.cycleRepeatMode()
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                // Lyrics - ⌘L
                Button(playerService.showLyrics ? "Hide Lyrics" : "Show Lyrics") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        playerService.showLyrics.toggle()
                    }
                }
                .keyboardShortcut("l", modifiers: .command)
            }

            // Navigation commands - replace default sidebar toggle
            CommandGroup(replacing: .sidebar) {
                // Home - ⌘1
                Button("Home") {
                    navigationSelection = .home
                }
                .keyboardShortcut("1", modifiers: .command)

                // Explore - ⌘2
                Button("Explore") {
                    navigationSelection = .explore
                }
                .keyboardShortcut("2", modifiers: .command)

                // Library - ⌘3
                Button("Library") {
                    navigationSelection = .library
                }
                .keyboardShortcut("3", modifiers: .command)

                Divider()

                // Search - ⌘F
                Button("Search") {
                    navigationSelection = .search
                    // Trigger focus after a brief delay to allow view to appear
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        searchFocusTrigger = true
                    }
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }
    }

    /// Label for repeat mode menu item.
    private var repeatModeLabel: String {
        switch playerService.repeatMode {
        case .off:
            "Repeat All"
        case .all:
            "Repeat One"
        case .one:
            "Repeat Off"
        }
    }
}
