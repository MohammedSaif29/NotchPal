// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let app = AppModel()
    private var island: IslandController?
    private var menuBar: MenuBarController?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Writing to the media helper after it exits must not crash the app.
        signal(SIGPIPE, SIG_IGN)

        let app = self.app
        installEditMenu()
        let settingsWindow = SettingsWindowController(app: app)
        self.settingsWindow = settingsWindow
        app.openSettings = { settingsWindow.show() }

        // Live alerts
        app.nowPlaying.onSongChange = { track in
            guard app.settings.songAlerts, app.state.mode != .expanded else { return }
            app.alerts.show(.nowPlaying(title: track.title))
        }
        app.power.onAlert = { alert in
            guard app.settings.batteryAlerts else { return }
            app.alerts.show(alert)
        }
        app.audio.onWirelessConnect = { output in
            guard app.settings.deviceAlerts else { return }
            app.alerts.show(.device(name: output.name, symbol: output.symbol))
        }
        app.audio.onOutputSwitch = { output in
            guard app.settings.deviceAlerts else { return }
            app.alerts.show(.audioSwitch(name: output.name, symbol: output.symbol))
        }
        app.timer.onFinish = {
            app.alerts.show(.timerDone)
        }
        app.calendar.onUpcoming = { event, minutes in
            app.alerts.show(.event(title: event.title, minutes: minutes, link: event.meetingURL?.absoluteString))
        }
        app.badges.onNewBadge = { badge in
            guard app.settings.messageAlerts, app.state.mode != .expanded else { return }
            app.alerts.show(.message(app: badge.name, count: badge.count, path: badge.path))
        }

        // Updates
        app.updates.onAvailable = { release in
            app.alerts.show(.updateAvailable(version: release.version))
        }
        app.updates.onFailure = { _ in
            app.alerts.dismiss(.update)
            app.alerts.show(.updateFailed)
        }
        app.updates.setAutomatic(app.settings.autoCheckUpdates)

        app.nowPlaying.start()
        app.audio.start()
        app.power.start()
        app.privacy.start()
        app.calendar.start()
        app.glow.start()
        if app.settings.liveActivities {
            app.activities.start()
        }
        app.badges.setEnabled(app.settings.badgesEnabled)

        // Search in the notch from any app.
        app.hotKey.onPress = { app.toggleSearch() }
        app.hotKey.register(app.settings.searchShortcut)

        island = IslandController(app: app)
        menuBar = MenuBarController(app: app)
        if app.settings.launchIntro {
            app.playIntro()
        }

        // Displays plugged in or out, or resolution changed: find the notch again.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.island?.reposition() }
        }

        // Just restarted after an update: say so, instead of the usual hello.
        // Both wait for the opening animation to finish.
        let defaults = UserDefaults.standard
        let helloDelay = app.state.introStart != nil ? LaunchIntro.duration - 0.25 : 0.6

        // New here: a tour of what NotchPal does. Just updated: a tour of what's new.
        // Someone who used NotchPal before has some of these saved already.
        let current = app.updates.currentVersion
        let seenTour = defaults.string(forKey: AppModel.tourSeenKey)
        let usedBefore = ["lastUpdateCheck", UpdateService.justUpdatedKey, "seenMusicApps", "quickNote", "glowStyle"]
            .contains { defaults.object(forKey: $0) != nil }
        var tour: TourKind?
        if seenTour == nil && !usedBefore {
            tour = .welcome
        } else if seenTour != current && Tours.versionsWithNews.contains(current) {
            tour = .whatsNew(version: current)
        }
        if let tour {
            defaults.removeObject(forKey: UpdateService.justUpdatedKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + helloDelay) {
                MainActor.assumeIsolated { app.startTour(tour) }
            }
        } else if let version = defaults.string(forKey: UpdateService.justUpdatedKey) {
            defaults.removeObject(forKey: UpdateService.justUpdatedKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + helloDelay) {
                MainActor.assumeIsolated { app.alerts.show(.updated(version: version)) }
            }
        } else if app.settings.sayHello {
            DispatchQueue.main.asyncAfter(deadline: .now() + helloDelay) {
                MainActor.assumeIsolated { app.alerts.show(.welcome) }
            }
        }
    }

    /// Menu bar apps don't show a menu bar of their own, but text boxes still need an Edit menu for
    /// copy, paste, cut, select all and undo shortcuts to work. This one is never visible.
    private func installEditMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu(title: "NotchPal")
        main.addItem(appItem)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    func applicationWillTerminate(_ notification: Notification) {
        app.nowPlaying.stop()
        app.camera.stop()
    }
}
