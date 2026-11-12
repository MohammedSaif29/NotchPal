// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// What the island is showing right now, in priority order.
enum IslandContent: Equatable {
    /// The search bar, like Spotlight in Apple's island.
    case search
    /// The guided tour.
    case tour
    case expanded
    case drop
    case alert(IslandAlert)
    case compact
    case idle
    /// Out of the way of a full-screen movie or game. Draws nothing and takes no clicks.
    case hidden
}

/// What the closed island's wings are about.
enum CompactKind: Equatable {
    case screenRecording
    case call
    case recording
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
    /// Diameter of the second little island that splits off for a second live activity, or 0.
    var bubble: CGFloat
}

/// One place that decides what the island shows and how big it is. The view draws it,
/// and the controller uses the same numbers to know where the mouse can click.
@MainActor
enum IslandLayout {
    static let bubbleGap: CGFloat = 6

    static func content(_ app: AppModel) -> IslandContent {
        if app.state.mode == .expanded {
            if app.state.searching { return .search }
            if app.state.tour != nil { return .tour }
            return .expanded
        }
        return closedContent(app)
    }

    /// What the notch shows when it isn't open. With the floating style, the notch keeps showing
    /// this while the open island floats below it.
    static func closedContent(_ app: AppModel) -> IslandContent {
        // The opening animation traces the real notch, so the island waits in it until that's done.
        if app.state.introStart != nil { return .idle }
        if app.state.isDropTargeted { return .drop }
        let hiding = hidesForFullScreen(app)
        if let alert = app.alerts.current {
            if !hiding || (app.settings.fullScreenAlerts && alert.showsInFullScreen) {
                return .alert(alert)
            }
        }
        // Hovering the notch always brings it back, so it's never out of reach.
        if hiding && app.state.mode == .collapsed { return .hidden }
        if showsClosedContent(app) && (hasLiveActivity(app) || hasAmbient(app)) { return .compact }
        return .idle
    }

    /// Over a full-screen movie or game, the closed island steps out of the way.
    static func hidesForFullScreen(_ app: AppModel) -> Bool {
        guard let fullScreen = app.state.fullScreenApp else { return false }
        switch app.settings.fullScreenHide {
        case .never: return false
        case .anyApp: return true
        case .watching: return isWatching(app, in: fullScreen)
        }
    }

    /// Apps that are for watching, so being full screen means a movie is on.
    private static let videoPlayers: Set<String> = [
        "com.apple.TV", "com.apple.QuickTimePlayerX", "com.colliderli.iina",
        "org.videolan.vlc", "com.firecore.infuse",
    ]

    /// Songs are short and movies and episodes are long, so music in a full-screen browser
    /// (YouTube Music, Spotify on the web) keeps the island.
    private static let shortestVideo: Double = 8 * 60

    /// A video is playing in the full-screen app: a video player, or the browser that's playing
    /// a movie or an episode. A paused video counts for a few more seconds, so pauses don't flicker.
    private static func isWatching(_ app: AppModel, in fullScreen: FullScreenApp) -> Bool {
        guard let bundleID = fullScreen.bundleID else { return false }
        if videoPlayers.contains(bundleID) { return true }
        guard app.nowPlaying.showsActivity, let track = app.nowPlaying.track else { return false }
        // No length at all usually means a live stream or a streaming site that doesn't say.
        let long = track.duration >= shortestVideo || track.duration <= 0
        return track.bundleID == bundleID && long
    }

    /// On Macs without a notch the closed island would sit on top of menu bar items, so by default
    /// it stays hidden there until you hover the top middle of the screen.
    static func showsClosedContent(_ app: AppModel) -> Bool {
        guard app.settings.closedWings else { return false }
        return app.state.notch.hasNotch || app.settings.noNotchMode == .menuBar
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

    /// Everything live right now, most important first, like Live Activities on Apple's island:
    /// a screen recording, a call, a recording, music, then a timer.
    static func liveItems(_ app: AppModel) -> [LiveItem] {
        var items: [LiveItem] = []
        if app.settings.liveActivities {
            let activities = app.activities
            if let screen = activities.screenRecording { items.append(screen) }
            if let call = activities.call { items.append(call) }
            if let recording = activities.recording { items.append(recording) }
        }
        if app.nowPlaying.showsActivity { items.append(LiveItem(kind: .music)) }
        if app.timer.isActive || app.timer.finished { items.append(LiveItem(kind: .timer)) }
        return items
    }

    static func hasLiveActivity(_ app: AppModel) -> Bool {
        !liveItems(app).isEmpty
    }

    static func compactKind(_ app: AppModel) -> CompactKind {
        switch liveItems(app).first?.kind {
        case .screenRecording: return .screenRecording
        case .call: return .call
        case .recording: return .recording
        case .music: return .music
        case .timer: return .timer
        case nil: return .ambient
        }
    }

    /// The live activity in the wings, if any.
    static func primaryItem(_ app: AppModel) -> LiveItem? {
        liveItems(app).first
    }

    /// The second live activity, which splits off into its own little island.
    static func bubbleItem(_ app: AppModel) -> LiveItem? {
        let items = liveItems(app)
        return items.count >= 2 ? items[1] : nil
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

    /// With two things live at once (music and a timer, a call and music), the first keeps the
    /// island and the second splits off into its own little island beside it, like a droplet.
    static func showsBubble(_ app: AppModel) -> Bool {
        app.settings.splitActivities && content(app) == .compact && bubbleItem(app) != nil
    }

    /// Whether the open island floats below the notch as its own widget, like Apple's new MacBook Pro.
    static func floats(_ app: AppModel) -> Bool {
        guard app.settings.openStyle == .floating else { return false }
        switch content(app) {
        case .expanded, .search, .tour: return true
        default: return false
        }
    }

    /// Space between the notch and the floating island.
    static let cardGap: CGFloat = 8

    /// The floating island's size, when it's floating.
    static func cardSize(_ app: AppModel) -> CGSize? {
        guard floats(app) else { return nil }
        let notch = app.state.notch
        let settings = app.settings
        switch content(app) {
        case .expanded:
            return CGSize(width: max(CGFloat(settings.openWidth), notch.width + 260), height: openHeight(app) + 38)
        case .search:
            return CGSize(width: max(CGFloat(settings.openWidth), 580), height: app.search.bodyHeight + 18)
        case .tour:
            return TourView.size
        default:
            return nil
        }
    }

    static func geometry(_ app: AppModel) -> IslandGeometry {
        // Floating: the notch keeps its closed shape and the island floats below it.
        geometry(app, for: floats(app) ? closedContent(app) : content(app))
    }

    static func geometry(_ app: AppModel, for content: IslandContent) -> IslandGeometry {
        let notch = app.state.notch
        let settings = app.settings
        let peek = app.state.mode == .peek
        let closedHeight = notch.height + CGFloat(settings.closedExtraHeight)

        switch content {
        case .tour:
            return IslandGeometry(
                size: CGSize(width: max(TourView.size.width, notch.width + 260), height: notch.height + TourView.size.height - 10),
                topRadius: 14, bottomRadius: 28, bubble: 0
            )
        case .search:
            return IslandGeometry(
                size: CGSize(width: max(CGFloat(settings.openWidth), notch.width + 360, 580),
                             height: notch.height + app.search.bodyHeight + 8),
                topRadius: 14, bottomRadius: 26, bubble: 0
            )
        case .expanded:
            return IslandGeometry(
                size: CGSize(width: max(CGFloat(settings.openWidth), notch.width + 260),
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
                wing = max(44, CGFloat(settings.wingWidth) * 0.85)
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
        case .hidden:
            // Shrinks up into the top edge of the screen.
            return IslandGeometry(size: CGSize(width: notch.width, height: 0), topRadius: 6, bottomRadius: 10, bubble: 0)
        }
    }
}
