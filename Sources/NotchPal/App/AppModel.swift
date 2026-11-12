// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
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
    let updates = UpdateService()
    let brightness = BrightnessService()
    let glow = GlowEngine()
    let activities = ActivityMonitor()
    let search = SearchService()
    let hotKey = GlobalHotKey()

    /// Set by the island controller: gives the island the keyboard, for search.
    var focusIsland: (@MainActor () -> Void)?

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
        search.app = self
    }

    /// Opens the notch as a search bar, from the shortcut or the 🔍 button.
    func openSearch() {
        search.reset()
        state.tour = nil
        state.holdOpenUntil = nil
        state.searching = true
        state.mode = .expanded
        focusIsland?()
    }

    func closeSearch() {
        guard state.searching else { return }
        state.searching = false
        closeIsland()
    }

    /// The shortcut opens search, and closes it again if it's already open.
    func toggleSearch() {
        if state.searching && state.mode == .expanded {
            closeSearch()
        } else {
            openSearch()
        }
    }

    // MARK: Tour

    /// The version whose tour (welcome or What's new) has been shown.
    static let tourSeenKey = "tourSeenVersion"

    /// Shows the tour in the notch, one card at a time.
    func startTour(_ kind: TourKind) {
        state.searching = false
        state.tour = TourState(kind: kind)
        state.holdOpenUntil = nil
        state.mode = .expanded
        UserDefaults.standard.set(updates.currentVersion, forKey: Self.tourSeenKey)
        focusIsland?()
    }

    func moveTour(by step: Int) {
        guard var tour = state.tour else { return }
        let count = Tours.steps(tour.kind, app: self).count
        tour.step = min(max(0, tour.step + step), count - 1)
        state.tour = tour
    }

    func endTour() {
        guard state.tour != nil else { return }
        state.tour = nil
        closeIsland()
    }

    func runTourAction(_ action: TourAction) {
        switch action {
        case .trySearch:
            state.tour = nil
            openSearch()
        case .askSiri:
            askSiri()
        case .openSettings:
            endTour()
            openSettings?()
        }
    }

    /// Opens Siri. The notch glows in Siri's colours while it listens.
    func askSiri() {
        glow.noteSiriOpened()
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Siri") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
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

    /// The opening animation around the notch. Skipped with Reduce Motion on.
    func playIntro() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let start = Date()
        state.introStart = start
        DispatchQueue.main.asyncAfter(deadline: .now() + LaunchIntro.duration) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.state.introStart == start else { return }
                self.state.introStart = nil
            }
        }
    }

    /// Opens macOS's own Video Effects panel and keeps the Mirror open beside it.
    func openVideoEffects() {
        state.effectsBaseline = VideoEffectsPanel.largeWindows(of: VideoEffectsPanel.controlCenterPID)
        state.effectsPanelOpenedAt = Date()
        camera.showVideoEffects()
    }
}
