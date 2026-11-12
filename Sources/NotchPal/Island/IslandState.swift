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
        case .home: return "music.note"
        case .calendar: return "calendar"
        case .camera: return "camera.fill"
        case .apps: return "square.grid.2x2.fill"
        case .inbox: return "bell.badge.fill"
        case .notes: return "note.text"
        case .timer: return "timer"
        case .play: return "gamecontroller.fill"
        }
    }

    var title: String {
        switch self {
        case .home: return "Music"
        case .calendar: return "Calendar"
        case .camera: return "Mirror"
        case .apps: return "Apps"
        case .inbox: return "Notifications"
        case .notes: return "Notes"
        case .timer: return "Timer"
        case .play: return "Games"
        }
    }

    var summary: String {
        switch self {
        case .home: return "Now playing, volume, speakers, AirDrop and battery"
        case .calendar: return "Today's events with one-click Join for meetings"
        case .camera: return "A quick camera mirror before calls"
        case .apps: return "Your favourite apps, one click away"
        case .inbox: return "Unread counts from Messages, WhatsApp, Mail and more"
        case .notes: return "A scratchpad that's always one hover away"
        case .timer: return "Quick timers and focus sessions"
        case .play: return "Runner, Flappy, Snake and Pong"
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
    /// When the opening animation started. The island stays the size of the notch while it plays.
    var introStart: Date?
    /// The island is open as a search bar.
    var searching = false
    /// The guided tour that explains NotchPal (or what's new), one card at a time.
    var tour: TourState?
    /// Where the pointer is just below the notch, for the black-hole effect. Nil when it's away.
    var pointer: CGPoint?

    var effectsPanelOpen: Bool { effectsPanelOpenedAt != nil }
}
