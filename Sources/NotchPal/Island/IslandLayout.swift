// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// What the island is showing right now, in priority order.
enum IslandContent: Equatable {
    case expanded
    case drop
    case alert(IslandAlert)
    case compact
    case idle
}

/// What the closed island's wings are about.
enum CompactKind: Equatable {
    case music
    case timer
    /// Pet, battery and privacy dots, when nothing else is live.
    case ambient
}

/// The island's size and corner shape for the current content.
struct IslandGeometry: Equatable {
    var size: CGSize
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    /// Diameter of the separate timer bubble, or 0 when there isn't one.
    var bubble: CGFloat
}

/// One place that decides what the island shows and how big it is. The view draws it,
/// and the controller uses the same numbers to know where the mouse can click.
@MainActor
enum IslandLayout {
    static let bubbleGap: CGFloat = 6

    static func content(_ app: AppModel) -> IslandContent {
        if app.state.mode == .expanded { return .expanded }
        if app.state.isDropTargeted { return .drop }
        if let alert = app.alerts.current { return .alert(alert) }
        if hasLiveActivity(app) || hasAmbient(app) { return .compact }
        return .idle
    }

    /// The Mirror tab makes the island a bit taller, so your whole face fits.
    static let mirrorOpenHeight: CGFloat = 240

    /// How far the open island reaches below the notch.
    static func openHeight(_ app: AppModel) -> CGFloat {
        let height = CGFloat(app.settings.openHeight)
        return app.state.tab == .camera ? max(height, mirrorOpenHeight) : height
    }

    /// Height left for a widget inside the open island, below the tab row.
    static func bodyHeight(_ app: AppModel) -> CGFloat {
        CGFloat(app.settings.openHeight) - 22
    }

    /// Short islands use tighter layouts so nothing gets cut off.
    static func isCompactBody(_ app: AppModel) -> Bool {
        bodyHeight(app) < 160
    }

    /// How big things inside the open island are, compared with the standard size.
    /// Album art, buttons and text grow and shrink with the Width and Length settings.
    static func contentScale(_ app: AppModel) -> CGFloat {
        let byHeight = bodyHeight(app) / 182
        let byWidth = CGFloat(app.settings.openWidth) / 560 * 1.1
        return min(1.45, max(0.72, min(byHeight, byWidth)))
    }

    static func hasLiveActivity(_ app: AppModel) -> Bool {
        app.nowPlaying.showsActivity || app.timer.isActive || app.timer.finished
    }

    static func compactKind(_ app: AppModel) -> CompactKind {
        if app.nowPlaying.showsActivity { return .music }
        if app.timer.isActive || app.timer.finished { return .timer }
        return .ambient
    }

    /// Whether the battery should sit in the closed notch right now.
    static func showsBattery(_ app: AppModel) -> Bool {
        let power = app.power
        guard power.hasBattery else { return false }
        switch app.settings.batteryDisplay {
        case .off: return false
        case .always: return true
        case .onBattery: return !power.onPower
        case .low: return power.level <= 20 && !power.isCharging
        case .charging: return power.isCharging
        }
    }

    static func showsPrivacyDots(_ app: AppModel) -> Bool {
        app.settings.privacyDots && app.privacy.inUse
    }

    static func hasAmbient(_ app: AppModel) -> Bool {
        app.settings.pet || showsBattery(app) || showsPrivacyDots(app)
    }

    /// With music and a timer at once, music keeps the island and the timer gets
    /// its own little bubble beside it, like two live activities on iPhone.
    static func showsBubble(_ app: AppModel) -> Bool {
        content(app) == .compact && app.nowPlaying.showsActivity && app.timer.isActive
    }

    static func geometry(_ app: AppModel) -> IslandGeometry {
        let notch = app.state.notch
        let settings = app.settings
        let peek = app.state.mode == .peek
        let closedHeight = notch.height + CGFloat(settings.closedExtraHeight)

        switch content(app) {
        case .expanded:
            return IslandGeometry(
                size: CGSize(width: max(CGFloat(settings.openWidth), notch.width + 300),
                             height: notch.height + openHeight(app)),
                topRadius: 14, bottomRadius: CGFloat(settings.cornerRadius), bubble: 0
            )
        case .drop:
            return IslandGeometry(
                size: CGSize(width: max(380, notch.width + 190), height: notch.height + 58),
                topRadius: 10, bottomRadius: 24, bubble: 0
            )
        case .alert(let alert):
            return IslandGeometry(
                size: CGSize(width: max(alert.width, notch.width + 200), height: notch.height + 52),
                topRadius: 10, bottomRadius: 26, bubble: 0
            )
        case .compact:
            let grow: CGFloat = peek ? 4 : 0
            let wing: CGFloat
            if hasLiveActivity(app) {
                wing = CGFloat(settings.wingWidth)
            } else if settings.pet || showsBattery(app) {
                wing = max(56, CGFloat(settings.wingWidth) * 0.85)
            } else {
                wing = 26 // Only the privacy dots.
            }
            let dotsRoom: CGFloat = showsPrivacyDots(app) && wing > 26 ? 14 : 0
            return IslandGeometry(
                size: CGSize(width: notch.width + (wing + dotsRoom) * 2 + grow * 4, height: closedHeight + grow),
                topRadius: 6, bottomRadius: peek ? 14 : 12,
                bubble: showsBubble(app) ? closedHeight + grow : 0
            )
        case .idle:
            if !notch.hasNotch && !peek && settings.closedExtraHeight == 0 {
                return IslandGeometry(size: CGSize(width: notch.width, height: 0), topRadius: 6, bottomRadius: 10, bubble: 0)
            }
            return IslandGeometry(
                size: CGSize(width: notch.width + (peek ? 22 : 0), height: closedHeight + (peek ? 5 : 0)),
                topRadius: 6, bottomRadius: peek ? 13 : 10, bubble: 0
            )
        }
    }
}
