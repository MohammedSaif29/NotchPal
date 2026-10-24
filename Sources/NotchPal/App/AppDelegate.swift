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
        app.badges.setEnabled(app.settings.badgesEnabled)

        island = IslandController(app: app)
        menuBar = MenuBarController(app: app)

        // Displays plugged in or out, or resolution changed: find the notch again.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.island?.reposition() }
        }

        // Just restarted after an update: say so, instead of the usual hello.
        let defaults = UserDefaults.standard
        if let version = defaults.string(forKey: UpdateService.justUpdatedKey) {
            defaults.removeObject(forKey: UpdateService.justUpdatedKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                MainActor.assumeIsolated { app.alerts.show(.updated(version: version)) }
            }
        } else if app.settings.sayHello {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                MainActor.assumeIsolated { app.alerts.show(.welcome) }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        app.nowPlaying.stop()
        app.camera.stop()
    }
}
