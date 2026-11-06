// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Observation
import SwiftUI

/// How the glow moves.
enum GlowRhythm: Equatable {
    /// Doesn't move: the resting ember, a song after its first few seconds, the camera light.
    case still
    /// Slow breathing.
    case breathe
    /// Pumps like a beat, for the first few seconds of a song.
    case groove
    /// A quick pulse: low battery, a timer that's done or about to be.
    case urgent
    /// Colours run along the edge: plugging in, saying hello.
    case flow
}

/// What's lighting the glow right now.
enum GlowSource: Equatable {
    case preview
    case alert
    case timer
    case privacy
    case music
    case meeting
    case ember

    var label: String {
        switch self {
        case .preview: "A preview"
        case .alert: "An alert"
        case .timer: "Your timer"
        case .privacy: "The camera or microphone"
        case .music: "What's playing"
        case .meeting: "A meeting about to start"
        case .ember: "The resting ember"
        }
    }
}

/// The glow around the island.
struct Glow: Equatable {
    /// Three colours, left to right along the edge. All the same for a calm, one-colour glow.
    var colors: [Color]
    var source: GlowSource
    var rhythm: GlowRhythm
    /// 0…1, before the Brightness setting.
    var strength: Double
    /// Changes when the glow changes for a new reason (a new song, a flash ending), so the old
    /// glow fades into the new one instead of jumping.
    var key: String
    /// For a still glow whose colour still changes slowly (a timer going from green to red):
    /// how often to redraw it, in seconds.
    var updateEvery: Double? = nil

    /// The same colour all along the edge.
    static func single(_ color: Color, source: GlowSource, strength: Double, key: String,
                       rhythm: GlowRhythm = .still, updateEvery: Double? = nil) -> Glow {
        Glow(colors: [color, color, color], source: source, rhythm: rhythm, strength: strength,
             key: key, updateEvery: updateEvery)
    }
}

/// Colours the glow uses for its own signals.
enum GlowColors {
    static let green = Color(red: 0.2, green: 0.86, blue: 0.42)
    static let mint = Color(red: 0.45, green: 1.0, blue: 0.72)
    static let yellow = Color(red: 1.0, green: 0.84, blue: 0.2)
    static let orange = Color(red: 1.0, green: 0.6, blue: 0.1)
    static let red = Color(red: 1.0, green: 0.26, blue: 0.24)
    static let blue = Color(red: 0.26, green: 0.56, blue: 1.0)
    static let cyan = Color(red: 0.3, green: 0.86, blue: 0.96)
    static let purple = Color(red: 0.64, green: 0.42, blue: 1.0)
    static let pink = Color(red: 1.0, green: 0.36, blue: 0.64)
    static let white = Color(white: 0.96)

    /// Deeper, richer versions of colours, so they show up on a light wallpaper. Whites and greys
    /// become a dark slate, since white light can't be seen on white.
    static func deepened(_ colors: [Color]) -> [Color] {
        colors.map { color in
            let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.white
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            ns.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            if saturation < 0.12 { return Color(white: 0.28) }
            return Color(hue: hue, saturation: min(1, max(saturation, 0.7) * 1.1), brightness: brightness * 0.78)
        }
    }

    /// A colour with a slightly lighter and a slightly deeper shade either side.
    static func shades(of color: Color) -> [Color] {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.white
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        ns.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return shades(hue: hue, saturation: saturation, brightness: brightness)
    }

    static func shades(hue: Double, saturation: Double, brightness: Double) -> [Color] {
        let wrap = { (value: Double) in value - floor(value) }
        return [
            Color(hue: wrap(hue - 0.035), saturation: saturation * 0.85, brightness: min(1, brightness + 0.08)),
            Color(hue: hue, saturation: saturation, brightness: brightness),
            Color(hue: wrap(hue + 0.035), saturation: min(1, saturation * 1.05), brightness: brightness * 0.82),
        ]
    }
}

/// Decides what the glow around the island looks like. It's calm by default: one dim, still
/// colour at rest. Only things that need a moment of attention move: a song starting pulses in
/// the album's colours for a few seconds and then settles into its main colour, alerts flash,
/// and a timer pulses in its last seconds. Still glows cost no battery.
@MainActor
@Observable
final class GlowEngine {
    /// Shows a sample glow on the notch for a few seconds (from Settings).
    private(set) var previewUntil: Date?
    /// Ticks when a glow should change on its own (a song's pulse ending, a meeting starting),
    /// and every 20 seconds just in case.
    private(set) var heartbeat = 0
    /// The wallpaper around the notch is light, so the glow uses deeper colours.
    private(set) var lightBackdrop = false
    @ObservationIgnored private var backdropURL: URL?
    @ObservationIgnored private var backdropObservers: [NSObjectProtocol] = []

    /// How long a new song pulses before it settles.
    static let songPulse: TimeInterval = 6

    @ObservationIgnored private var iconCache: [String: [Color]] = [:]
    @ObservationIgnored private var artworkCache: (image: NSImage, colors: [Color])?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var song: String?
    @ObservationIgnored private var songStarted: Date?
    /// The last song's main colour, which the ember takes when the accent is "match album art".
    @ObservationIgnored private var lastSongColor: Color?
    @ObservationIgnored private var pendingRefreshes: Set<Int> = []

    func start() {
        guard ticker == nil else { return }
        // Before the opening animation, so it already knows which colours will show up.
        checkBackdrop(now: true)

        let tick = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.heartbeat &+= 1
                self?.checkBackdrop()
            }
        }
        RunLoop.main.add(tick, forMode: .common)
        ticker = tick

        // Each desktop Space can have its own wallpaper.
        let changes: [(NotificationCenter, Notification.Name)] = [
            (NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification),
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification),
        ]
        for (center, name) in changes {
            backdropObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkBackdrop(force: true) }
            })
        }
    }

    /// Looks at the wallpaper again if it changed. `now` reads it straight away instead of in the
    /// background.
    private func checkBackdrop(now: Bool = false, force: Bool = false) {
        guard let url = BackdropProbe.wallpaperURL() else { return }
        guard force || url != backdropURL else { return }
        backdropURL = url
        if now {
            apply(BackdropProbe.brightness(of: url))
            return
        }
        Task.detached(priority: .utility) { [weak self] in
            let brightness = BackdropProbe.brightness(of: url)
            await MainActor.run { self?.apply(brightness) }
        }
    }

    private func apply(_ brightness: Double?) {
        // A wallpaper that can't be read keeps the usual light-on-dark look.
        let light = (brightness ?? 0) > 0.6
        if lightBackdrop != light { lightBackdrop = light }
    }

    func showPreview(seconds: TimeInterval = 4) {
        let until = Date().addingTimeInterval(seconds)
        previewUntil = until
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.05) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.previewUntil == until else { return }
                self.previewUntil = nil
            }
        }
    }

    /// Asks the island to look again at a moment when the glow changes by itself.
    private func refresh(at date: Date) {
        let slot = Int(date.timeIntervalSince1970.rounded())
        guard date > Date(), !pendingRefreshes.contains(slot) else { return }
        pendingRefreshes.insert(slot)
        DispatchQueue.main.asyncAfter(deadline: .now() + date.timeIntervalSinceNow + 0.05) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pendingRefreshes.remove(slot)
                self.heartbeat &+= 1
            }
        }
    }

    // MARK: What glows

    func current(_ app: AppModel, content: IslandContent, now: Date = .now) -> Glow? {
        // The opening animation has its own light; the normal glow fades in after it.
        guard content != .hidden, app.state.introStart == nil else { return nil }
        if let previewUntil, now < previewUntil {
            return Glow(colors: [GlowColors.pink, GlowColors.purple, GlowColors.cyan],
                        source: .preview, rhythm: .flow, strength: 1, key: "preview")
        }
        let settings = app.settings
        guard settings.glowEnabled else { return nil }

        if settings.glowAlerts, let alert = app.alerts.current, let glow = alertGlow(alert) {
            return glow
        }
        if settings.glowTimer, app.timer.finished {
            return Glow(colors: [GlowColors.red, GlowColors.orange, GlowColors.red],
                        source: .timer, rhythm: .urgent, strength: 1, key: "timer-done")
        }
        if settings.glowPrivacy, app.privacy.inUse {
            // Green for the camera and orange for the microphone, like the dots on iPhone.
            let color = app.privacy.cameraInUse ? GlowColors.green : GlowColors.orange
            return .single(color, source: .privacy, strength: 0.6, key: "privacy-\(app.privacy.cameraInUse)")
        }
        if settings.glowTimer, app.timer.isActive {
            return timerGlow(app.timer, now: now)
        }
        if settings.glowMusic, app.nowPlaying.isPlaying, app.nowPlaying.track != nil {
            return musicGlow(app, now: now)
        }
        if settings.glowAlerts, let glow = meetingGlow(app, now: now) {
            return glow
        }
        return restingGlow(settings)
    }

    private func alertGlow(_ alert: IslandAlert) -> Glow? {
        switch alert {
        case .welcome:
            return Glow(colors: [GlowColors.pink, GlowColors.purple, GlowColors.cyan],
                        source: .alert, rhythm: .flow, strength: 1, key: "welcome")
        case .charging:
            return Glow(colors: [GlowColors.green, GlowColors.mint, GlowColors.green],
                        source: .alert, rhythm: .flow, strength: 1, key: "charging")
        case .lowBattery:
            return Glow(colors: [GlowColors.red, GlowColors.orange, GlowColors.red],
                        source: .alert, rhythm: .urgent, strength: 1, key: "low-battery")
        case .device:
            return Glow(colors: [GlowColors.white, GlowColors.cyan, GlowColors.white],
                        source: .alert, rhythm: .breathe, strength: 0.9, key: "device")
        case .timerDone:
            return Glow(colors: [GlowColors.red, GlowColors.orange, GlowColors.red],
                        source: .alert, rhythm: .urgent, strength: 1, key: "timer-done")
        case .event:
            return Glow(colors: [GlowColors.blue, GlowColors.purple, GlowColors.blue],
                        source: .alert, rhythm: .urgent, strength: 0.95, key: "event")
        case .message:
            return Glow(colors: [GlowColors.blue, GlowColors.cyan, GlowColors.blue],
                        source: .alert, rhythm: .urgent, strength: 0.9, key: "message")
        case .updateAvailable, .updated:
            return Glow(colors: [GlowColors.purple, GlowColors.pink, GlowColors.orange],
                        source: .alert, rhythm: .flow, strength: 0.9, key: "update")
        case .updateFailed:
            return Glow(colors: [GlowColors.orange, GlowColors.red, GlowColors.orange],
                        source: .alert, rhythm: .breathe, strength: 0.9, key: "update-failed")
        case .nowPlaying, .updating:
            // A new song already pulses in the music glow; an update in progress needs no light.
            return nil
        }
    }

    /// One still colour, from green with plenty of time left, through yellow, to red. It pulses
    /// only in the last ten seconds.
    private func timerGlow(_ timer: TimerService, now: Date) -> Glow {
        let remaining = timer.remaining(at: now)
        let left = timer.total > 0 ? min(1, max(0, remaining / timer.total)) : 0
        let color = Color(hue: 0.34 * pow(left, 0.85), saturation: 0.86, brightness: 1)
        if timer.isPaused {
            return .single(color, source: .timer, strength: 0.4, key: "timer")
        }
        if remaining <= 10 {
            return .single(color, source: .timer, strength: 0.95, key: "timer-ending", rhythm: .urgent)
        }
        refresh(at: now.addingTimeInterval(remaining - 10))
        return .single(color, source: .timer, strength: 0.7, key: "timer", updateEvery: 1)
    }

    /// A new song pulses in the album art's colours for a few seconds, then settles into the
    /// album's main colour and holds still.
    private func musicGlow(_ app: AppModel, now: Date) -> Glow {
        let player = app.nowPlaying
        var colors: [Color]?
        if let artwork = player.artwork {
            colors = artworkColors(artwork)
        }
        if colors == nil, let bundleID = player.track?.bundleID {
            colors = iconColors(bundleID: bundleID, icon: player.appIcon)
        }
        let palette = colors ?? GlowColors.shades(of: app.accent)
        let main = palette[palette.count / 2]
        lastSongColor = main

        let title = "\(player.track?.title ?? "")|\(player.track?.artist ?? "")"
        if title != song {
            song = title
            songStarted = now
            refresh(at: now.addingTimeInterval(Self.songPulse))
        }
        if let started = songStarted, now.timeIntervalSince(started) < Self.songPulse {
            return Glow(colors: palette, source: .music, rhythm: .groove, strength: 0.95, key: "song-start-\(title)")
        }
        return .single(main, source: .music, strength: 0.55, key: "song-\(title)-\(main.hexString)")
    }

    /// A still glow in the calendar's colour while a meeting is about to start.
    private func meetingGlow(_ app: AppModel, now: Date) -> Glow? {
        let lead = Double(max(1, app.settings.calendarLeadMinutes)) * 60
        guard let event = app.calendar.events.first(where: {
            !$0.isAllDay && $0.start > now && $0.start.timeIntervalSince(now) <= lead
        }) else { return nil }
        refresh(at: event.start)
        return .single(event.color, source: .meeting, strength: 0.6, key: "meeting-\(event.id)")
    }

    /// One dim, still colour: your accent colour, or the last song's colour when the accent is
    /// set to match the album art, or your Mac's accent colour before any song has played.
    private func restingGlow(_ settings: SettingsStore) -> Glow? {
        switch settings.glowIdle {
        case .off:
            return nil
        case .ember:
            let color = settings.accent.fixedColor ?? lastSongColor ?? Color(nsColor: .controlAccentColor)
            return .single(color, source: .ember, strength: 0.38, key: "ember")
        }
    }

    // MARK: Colours from pictures

    private func iconColors(bundleID: String, icon: NSImage?) -> [Color]? {
        if let cached = iconCache[bundleID] { return cached }
        guard let colors = icon?.glowPalette() else { return nil }
        iconCache[bundleID] = colors
        return colors
    }

    private func artworkColors(_ image: NSImage) -> [Color]? {
        if let cache = artworkCache, cache.image === image { return cache.colors }
        guard let colors = image.glowPalette() else { return nil }
        artworkCache = (image, colors)
        return colors
    }
}

extension NSImage {
    /// Three bright colours from the picture for the glow: its main colour in the middle and
    /// the next ones either side. Black-and-white pictures get a soft white glow.
    func glowPalette() -> [Color]? {
        var proposed = CGRect(x: 0, y: 0, width: 64, height: 64)
        guard let cgImage = cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return nil }
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drew: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drew else { return nil }

        // Group the pixels into 12 hues, counting vivid pixels more than dull ones.
        var bins = [HueBin](repeating: HueBin(), count: 12)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0.6 else { continue } // The see-through parts of an app icon.
            let red = min(1, Double(pixels[index]) / 255 / alpha)
            let green = min(1, Double(pixels[index + 1]) / 255 / alpha)
            let blue = min(1, Double(pixels[index + 2]) / 255 / alpha)
            let color = HSV(red: red, green: green, blue: blue)
            guard color.value > 0.14, color.saturation > 0.2 else { continue }
            let weight = color.saturation * color.saturation * (0.3 + color.value)
            bins[min(11, Int(color.hue * 12))].add(red, green, blue, weight: weight)
        }

        let ranked = bins.indices.filter { bins[$0].weight > 0 }.sorted { bins[$0].weight > bins[$1].weight }
        guard let top = ranked.first, bins[top].weight > 1.2 else {
            return [Color(white: 0.72), Color(white: 0.97), Color(white: 0.72)]
        }
        var picked = [top]
        for index in ranked.dropFirst() where picked.count < 3 {
            guard bins[index].weight >= bins[top].weight * 0.1 else { break }
            // Skip hues right next to one already picked, so the colours really differ.
            let near = picked.contains { other in
                let gap = abs(other - index)
                return min(gap, 12 - gap) < 2
            }
            if !near { picked.append(index) }
        }

        let colors = picked.map { bins[$0].vivid }
        switch colors.count {
        case 1:
            let main = bins[top].averageHSV
            return GlowColors.shades(hue: main.hue,
                                     saturation: min(1, max(main.saturation, 0.55) * 1.08),
                                     brightness: max(main.value, 0.9))
        case 2:
            return [colors[1], colors[0], colors[1]]
        default:
            return [colors[1], colors[0], colors[2]]
        }
    }
}

private struct HSV {
    var hue: Double
    var saturation: Double
    var value: Double

    init(red: Double, green: Double, blue: Double) {
        let high = max(red, green, blue)
        let low = min(red, green, blue)
        let delta = high - low
        var hue = 0.0
        if delta > 0 {
            if high == red {
                hue = (green - blue) / delta
            } else if high == green {
                hue = (blue - red) / delta + 2
            } else {
                hue = (red - green) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        self.hue = hue
        saturation = high > 0 ? delta / high : 0
        value = high
    }
}

private struct HueBin {
    var red = 0.0
    var green = 0.0
    var blue = 0.0
    var weight = 0.0

    mutating func add(_ r: Double, _ g: Double, _ b: Double, weight w: Double) {
        red += r * w
        green += g * w
        blue += b * w
        weight += w
    }

    var averageHSV: HSV {
        guard weight > 0 else { return HSV(red: 1, green: 1, blue: 1) }
        return HSV(red: red / weight, green: green / weight, blue: blue / weight)
    }

    /// The bin's colour, brightened so it glows instead of looking muddy.
    var vivid: Color {
        let color = averageHSV
        return Color(hue: color.hue,
                     saturation: min(1, max(color.saturation, 0.55) * 1.08),
                     brightness: max(color.value, 0.9))
    }
}
