// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// Holds every service and the island's state, so views and controllers share one source of truth.
@MainActor
final class AppModel {
    let settings: SettingsStore
    let state = IslandState()
    let nowPlaying = NowPlayingService()
    let audio = AudioService()
    let timer = TimerService()
    let power = PowerService()
    let alerts = AlertCenter()
    let privacy = PrivacyMonitor()
    let badges = BadgeMonitor()
    let camera = CameraService()
    let shelf = AppShelf()
    let notes = NotesStore()
    let calendar: CalendarService
    let games: GameHub
    let settingsNavigation = SettingsNavigation()

    /// Set by the app delegate.
    var openSettings: (@MainActor () -> Void)?

    init() {
        let settings = SettingsStore()
        self.settings = settings
        calendar = CalendarService(settings: settings)
        games = GameHub(settings: settings)
        nowPlaying.isHidden = { bundleID in
            settings.hiddenMusicApps.contains(bundleID)
        }
        nowPlaying.onAppSeen = { bundleID in
            if !settings.seenMusicApps.contains(bundleID) {
                settings.seenMusicApps = settings.seenMusicApps + [bundleID]
            }
        }
    }

    /// The tint used across the island: the user's pick, or the album art's colour.
    var accent: Color {
        settings.accent.fixedColor ?? nowPlaying.artworkColor ?? Color(red: 1.0, green: 0.58, blue: 0.2)
    }

    /// Opens the island. `hold` keeps it open for that many seconds even if the mouse is elsewhere,
    /// so buttons like "Try it on the notch" in Settings have time to show it off.
    func openIsland(tab: IslandTab? = nil, hold: TimeInterval = 0) {
        state.holdOpenUntil = hold > 0 ? Date().addingTimeInterval(hold) : nil
        if let tab {
            state.tab = tab
        } else if timer.finished {
            state.tab = .timer
        } else if let preferred = IslandTab(rawValue: settings.openTo), settings.visibleTabs.contains(preferred) {
            state.tab = preferred
        }
        if tab == nil && !settings.visibleTabs.contains(state.tab) {
            state.tab = settings.visibleTabs.first ?? .home
        }
        state.mode = .expanded
    }

    func closeIsland() {
        state.mode = .collapsed
    }

    /// Opens macOS's own Video Effects panel and keeps the Mirror open beside it.
    func openVideoEffects() {
        state.effectsBaseline = VideoEffectsPanel.largeWindows(of: VideoEffectsPanel.controlCenterPID)
        state.effectsPanelOpenedAt = Date()
        camera.showVideoEffects()
    }
}
