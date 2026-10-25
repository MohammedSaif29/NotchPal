// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Observation

/// Where the island is in its life: hidden in the notch, peeking on hover, or open.
enum IslandMode: Equatable {
    case collapsed
    case peek
    case expanded
}

/// The widgets you can show in the open island. Turn them on, off, and reorder them in Settings.
enum IslandTab: String, CaseIterable, Identifiable {
    case home
    case calendar
    case camera
    case apps
    case inbox
    case notes
    case timer
    case play

    var id: Self { self }

    var symbol: String {
        switch self {
        case .home: "music.note"
        case .calendar: "calendar"
        case .camera: "camera.fill"
        case .apps: "square.grid.2x2.fill"
        case .inbox: "bell.badge.fill"
        case .notes: "note.text"
        case .timer: "timer"
        case .play: "gamecontroller.fill"
        }
    }

    var title: String {
        switch self {
        case .home: "Music"
        case .calendar: "Calendar"
        case .camera: "Mirror"
        case .apps: "Apps"
        case .inbox: "Notifications"
        case .notes: "Notes"
        case .timer: "Timer"
        case .play: "Games"
        }
    }

    var summary: String {
        switch self {
        case .home: "Now playing, volume, speakers, AirDrop and battery"
        case .calendar: "Today's events with one-click Join for meetings"
        case .camera: "A quick camera mirror before calls"
        case .apps: "Your favourite apps, one click away"
        case .inbox: "Unread counts from Messages, WhatsApp, Mail and more"
        case .notes: "A scratchpad that's always one hover away"
        case .timer: "Quick timers and focus sessions"
        case .play: "Runner, Flappy, Snake and Pong"
        }
    }
}

/// The size of the hardware notch (or a pretend one on Macs without a notch).
struct NotchGeometry: Equatable {
    var hasNotch: Bool
    var width: CGFloat
    var height: CGFloat

    static func detect(for screen: NSScreen) -> NotchGeometry {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            return NotchGeometry(hasNotch: true, width: width, height: screen.safeAreaInsets.top)
        }
        // No notch: act like a small pill under the middle of the menu bar.
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        return NotchGeometry(hasNotch: false, width: 180, height: max(menuBarHeight, 24))
    }
}

/// Shared UI state for the island.
@MainActor
@Observable
final class IslandState {
    var mode: IslandMode = .collapsed
    var tab: IslandTab = .home
    var isDropTargeted = false
    var notch = NotchGeometry(hasNotch: true, width: 185, height: 32)
    /// Keeps the island open until this time even if the mouse is elsewhere.
    var holdOpenUntil: Date?
    /// When macOS's Video Effects panel was opened from the Mirror. While it's open, the island
    /// stays open with the camera on beside it, so you can watch each effect change.
    var effectsPanelOpenedAt: Date?
    /// Control Center's big windows from before the panel opened, so the panel can be told apart.
    @ObservationIgnored var effectsBaseline: Set<Int> = []
    /// The app that's full screen on the notch's screen, if any.
    var fullScreenApp: FullScreenApp?

    var effectsPanelOpen: Bool { effectsPanelOpenedAt != nil }
}
