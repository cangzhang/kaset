import AppKit
import UserNotifications

// MARK: - AppDelegate

/// App delegate to control application lifecycle behavior.
/// Keeps the app running when windows are closed so audio playback continues.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        // Set up notification center delegate to show notifications in foreground
        UNUserNotificationCenter.current().delegate = self

        // Set up window delegate to intercept close and hide instead
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            self.setupWindowDelegate()
        }
    }

    private func setupWindowDelegate() {
        for window in NSApplication.shared.windows where window.canBecomeMain {
            window.delegate = self
        }
    }

    // MARK: - Dock Menu

    func applicationDockMenu(_: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        let playPauseItem = NSMenuItem(
            title: "Play/Pause",
            action: #selector(dockMenuPlayPause),
            keyEquivalent: ""
        )
        playPauseItem.target = self
        menu.addItem(playPauseItem)

        let nextItem = NSMenuItem(
            title: "Next Track",
            action: #selector(dockMenuNext),
            keyEquivalent: ""
        )
        nextItem.target = self
        menu.addItem(nextItem)

        let previousItem = NSMenuItem(
            title: "Previous Track",
            action: #selector(dockMenuPrevious),
            keyEquivalent: ""
        )
        previousItem.target = self
        menu.addItem(previousItem)

        return menu
    }

    @objc private func dockMenuPlayPause() {
        SingletonPlayerWebView.shared.playPause()
    }

    @objc private func dockMenuNext() {
        SingletonPlayerWebView.shared.next()
    }

    @objc private func dockMenuPrevious() {
        SingletonPlayerWebView.shared.previous()
    }

    /// Keep app running when the window is closed (for background audio).
    /// Use Cmd+Q to fully quit.
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    /// Handle reopen (clicking dock icon) when all windows are closed.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // Reopen the main window if it was closed
            for window in NSApplication.shared.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
                return true
            }
        }
        return true
    }
}

// MARK: NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    /// Intercept window close and hide instead, keeping WebView alive for background audio.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide the window instead of closing it
        sender.orderOut(nil)
        return false // Don't actually close
    }
}

// MARK: UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Show notifications even when the app is in the foreground.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner and play sound (if any) even when app is in foreground
        completionHandler([.banner])
    }
}
