// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI
import Observation

enum IslandStyle: String, CaseIterable, Identifiable {
    case black
    case glass      // Liquid Glass
    case frosted
    case clear

    var id: Self { self }

    var label: String {
        switch self {
        case .black: "Black"
        case .glass: "Liquid Glass"
        case .frosted: "Frosted"
        case .clear: "Clear"
        }
    }

    var isGlass: Bool { self != .black }
}

enum SizePreset: String, CaseIterable, Identifiable {
    case compact
    case standard
    case large

    var id: Self { self }

    var label: String {
        switch self {
        case .compact: "Compact"
        case .standard: "Standard"
        case .large: "Large"
        }
    }

    var width: Double {
        switch self {
        case .compact: 480
        case .standard: 560
        case .large: 660
        }
    }

    var height: Double {
        switch self {
        case .compact: 180
        case .standard: 204
        case .large: 244
        }
    }
}

enum MotionStyle: String, CaseIterable, Identifiable {
    case snappy
    case smooth
    case bouncy

    var id: Self { self }

    var label: String {
        switch self {
        case .snappy: "Snappy"
        case .smooth: "Smooth"
        case .bouncy: "Bouncy"
        }
    }

    var spring: Animation {
        switch self {
        case .snappy: .spring(response: 0.3, dampingFraction: 0.86)
        case .smooth: .spring(response: 0.46, dampingFraction: 0.8)
        case .bouncy: .spring(response: 0.52, dampingFraction: 0.62)
        }
    }
}

enum AccentChoice: String, CaseIterable, Identifiable {
    case artwork
    case orange
    case blue
    case purple
    case pink
    case green
    case teal

    var id: Self { self }

    var label: String {
        switch self {
        case .artwork: "Match album art"
        case .orange: "Orange"
        case .blue: "Blue"
        case .purple: "Purple"
        case .pink: "Pink"
        case .green: "Green"
        case .teal: "Teal"
        }
    }

    /// Nil for "match album art".
    var fixedColor: Color? {
        switch self {
        case .artwork: nil
        case .orange: Color(red: 1.0, green: 0.58, blue: 0.2)
        case .blue: Color(red: 0.3, green: 0.6, blue: 1.0)
        case .purple: Color(red: 0.68, green: 0.45, blue: 1.0)
        case .pink: Color(red: 1.0, green: 0.38, blue: 0.64)
        case .green: Color(red: 0.32, green: 0.86, blue: 0.47)
        case .teal: Color(red: 0.22, green: 0.82, blue: 0.86)
        }
    }
}

enum GlassTint: String, CaseIterable, Identifiable {
    case none
    case accent
    case custom

    var id: Self { self }

    var label: String {
        switch self {
        case .none: "None"
        case .accent: "Accent"
        case .custom: "Custom"
        }
    }
}

enum Difficulty: String, CaseIterable, Identifiable {
    case easy
    case normal
    case hard

    var id: Self { self }

    var label: String {
        switch self {
        case .easy: "Easy"
        case .normal: "Normal"
        case .hard: "Hard"
        }
    }
}

/// When the battery shows in the closed notch.
enum BatteryDisplay: String, CaseIterable, Identifiable {
    case off
    case always
    case onBattery
    case low
    case charging

    var id: Self { self }

    var label: String {
        switch self {
        case .off: "Never"
        case .always: "Always"
        case .onBattery: "When unplugged"
        case .low: "Only when low (20% or less)"
        case .charging: "While charging"
        }
    }
}

enum BatteryStyle: String, CaseIterable, Identifiable {
    case ring
    case pill
    case percent
    case minimal
    case emoji

    var id: Self { self }

    var label: String {
        switch self {
        case .ring: "Ring"
        case .pill: "Pill"
        case .percent: "Classic"
        case .minimal: "Number"
        case .emoji: "Emoji"
        }
    }
}

/// The shape of the camera mirror.
enum MirrorShape: String, CaseIterable, Identifiable {
    case circle
    case rectangle

    var id: Self { self }

    var label: String {
        switch self {
        case .circle: "Round"
        case .rectangle: "Rectangle"
        }
    }

    var symbol: String {
        switch self {
        case .circle: "circle"
        case .rectangle: "rectangle"
        }
    }
}

enum BatteryColorMode: String, CaseIterable, Identifiable {
    case auto
    case accent
    case custom

    var id: Self { self }

    var label: String {
        switch self {
        case .auto: "Like iPhone"
        case .accent: "Accent"
        case .custom: "Custom"
        }
    }
}

/// Funny emoji sets that change with the battery level.
enum EmojiPack: String, CaseIterable, Identifiable {
    case moods
    case hearts
    case animals
    case weather
    case food
    case space

    var id: Self { self }

    var label: String {
        switch self {
        case .moods: "Moods"
        case .hearts: "Hearts"
        case .animals: "Animals"
        case .weather: "Weather"
        case .food: "Snacks"
        case .space: "Space"
        }
    }

    /// From full to empty: 90%+, 70%+, 50%+, 30%+, 15%+, below 15%.
    var levels: [String] {
        switch self {
        case .moods: ["🤩", "😄", "🙂", "😐", "😰", "💀"]
        case .hearts: ["💖", "💚", "💛", "🧡", "❤️‍🩹", "💔"]
        case .animals: ["🐆", "🐎", "🐕", "🐢", "🦥", "🪦"]
        case .weather: ["☀️", "🌤️", "⛅️", "🌥️", "🌧️", "⛈️"]
        case .food: ["🍔", "🍟", "🍕", "🍪", "🥠", "🦴"]
        case .space: ["🚀", "🛸", "🌍", "🌗", "🌑", "☄️"]
        }
    }

    var chargingEmoji: String {
        switch self {
        case .moods: "😋"
        case .hearts: "💞"
        case .animals: "🐝"
        case .weather: "🌈"
        case .food: "🍳"
        case .space: "🌞"
        }
    }

    func emoji(level: Int, charging: Bool) -> String {
        if charging { return chargingEmoji }
        let thresholds = [90, 70, 50, 30, 15]
        for (index, threshold) in thresholds.enumerated() where level >= threshold {
            return levels[index]
        }
        return levels[5]
    }
}

/// Every user setting, saved automatically.
@MainActor
@Observable
final class SettingsStore {
    // Size
    var openWidth: Double { didSet { Self.save(openWidth, "openWidth") } }
    var openHeight: Double { didSet { Self.save(openHeight, "openHeight") } }
    var cornerRadius: Double { didSet { Self.save(cornerRadius, "cornerRadius") } }
    var wingWidth: Double { didSet { Self.save(wingWidth, "wingWidth") } }
    var closedExtraHeight: Double { didSet { Self.save(closedExtraHeight, "closedExtraHeight") } }

    // Look
    var style: IslandStyle { didSet { Self.save(style.rawValue, "style") } }
    var motion: MotionStyle { didSet { Self.save(motion.rawValue, "motion") } }
    var accent: AccentChoice { didSet { Self.save(accent.rawValue, "accent") } }
    var glassDarkness: Double { didSet { Self.save(glassDarkness, "glassDarkness") } }
    var glassTint: GlassTint { didSet { Self.save(glassTint.rawValue, "glassTint") } }
    var glassTintHex: String { didSet { Self.save(glassTintHex, "glassTintHex") } }
    var glassBorder: Bool { didSet { Self.save(glassBorder, "glassBorder") } }
    var glassWhenClosed: Bool { didSet { Self.save(glassWhenClosed, "glassWhenClosed") } }
    /// Fade the top of a glass island into black, so it looks like it grows out of the notch.
    var glassBlendTop: Bool { didSet { Self.save(glassBlendTop, "glassBlendTop") } }
    var shadowStrength: Double { didSet { Self.save(shadowStrength, "shadowStrength") } }

    // Behaviour
    var openOnHover: Bool { didSet { Self.save(openOnHover, "openOnHover") } }
    var hoverDelay: Double { didSet { Self.save(hoverDelay, "hoverDelay") } }
    var haptics: Bool { didSet { Self.save(haptics, "haptics") } }
    var sayHello: Bool { didSet { Self.save(sayHello, "sayHello") } }
    var swipeGestures: Bool { didSet { Self.save(swipeGestures, "swipeGestures") } }

    // Widgets (tabs in the open island)
    var tabOrder: [IslandTab] { didSet { Self.save(tabOrder.map(\.rawValue), "tabOrder") } }
    var hiddenTabs: Set<IslandTab> { didSet { Self.save(hiddenTabs.map(\.rawValue), "hiddenTabs") } }
    /// "last", or the raw value of the tab to open with.
    var openTo: String { didSet { Self.save(openTo, "openTo") } }

    // Closed notch extras
    var pet: Bool { didSet { Self.save(pet, "pet") } }
    var privacyDots: Bool { didSet { Self.save(privacyDots, "privacyDots") } }

    // Music
    var showArtworkInNotch: Bool { didSet { Self.save(showArtworkInNotch, "showArtworkInNotch") } }
    var showVisualizer: Bool { didSet { Self.save(showVisualizer, "showVisualizer") } }
    var songAlerts: Bool { didSet { Self.save(songAlerts, "songAlerts") } }
    /// Show the playing app's icon on the album art, like Spotify's logo.
    var showSourceBadge: Bool { didSet { Self.save(showSourceBadge, "showSourceBadge") } }
    /// Apps whose sound never shows in the notch, by bundle ID.
    var hiddenMusicApps: [String] { didSet { Self.save(hiddenMusicApps, "hiddenMusicApps") } }
    /// Apps NotchPal has seen playing, so Settings can list them.
    var seenMusicApps: [String] { didSet { Self.save(seenMusicApps, "seenMusicApps") } }

    // Battery
    var batteryDisplay: BatteryDisplay { didSet { Self.save(batteryDisplay.rawValue, "batteryDisplay") } }
    var batteryStyle: BatteryStyle { didSet { Self.save(batteryStyle.rawValue, "batteryStyle2") } }
    var emojiPack: EmojiPack { didSet { Self.save(emojiPack.rawValue, "emojiPack") } }
    var batteryColorMode: BatteryColorMode { didSet { Self.save(batteryColorMode.rawValue, "batteryColorMode") } }
    var batteryColorHex: String { didSet { Self.save(batteryColorHex, "batteryColorHex") } }
    var batteryPercentSign: Bool { didSet { Self.save(batteryPercentSign, "batteryPercentSign") } }
    var batteryAlerts: Bool { didSet { Self.save(batteryAlerts, "batteryAlerts") } }

    // Alerts and sources
    var deviceAlerts: Bool { didSet { Self.save(deviceAlerts, "deviceAlerts") } }
    var badgesEnabled: Bool { didSet { Self.save(badgesEnabled, "badgesEnabled") } }
    var messageAlerts: Bool { didSet { Self.save(messageAlerts, "messageAlerts") } }
    var calendarAlerts: Bool { didSet { Self.save(calendarAlerts, "calendarAlerts") } }
    var calendarLeadMinutes: Int { didSet { Self.save(calendarLeadMinutes, "calendarLeadMinutes") } }
    var showAllDayEvents: Bool { didSet { Self.save(showAllDayEvents, "showAllDayEvents") } }
    var mirrorFlip: Bool { didSet { Self.save(mirrorFlip, "mirrorFlip") } }
    var mirrorShape: MirrorShape { didSet { Self.save(mirrorShape.rawValue, "mirrorShape") } }

    // Games
    var difficulty: Difficulty { didSet { Self.save(difficulty.rawValue, "difficulty") } }
    var gameSounds: Bool { didSet { Self.save(gameSounds, "gameSounds") } }
    var lastGame: String { didSet { Self.save(lastGame, "lastGame") } }

    init() {
        let stored = UserDefaults.standard
        let legacySize = SizePreset(rawValue: stored.string(forKey: "size") ?? "") ?? .standard

        openWidth = Self.clamp(stored.object(forKey: "openWidth") as? Double ?? legacySize.width, 480...800)
        openHeight = Self.clamp(stored.object(forKey: "openHeight") as? Double ?? legacySize.height, 150...320)
        cornerRadius = Self.clamp(stored.object(forKey: "cornerRadius") as? Double ?? 34, 12...56)
        wingWidth = Self.clamp(stored.object(forKey: "wingWidth") as? Double ?? 70, 44...120)
        closedExtraHeight = Self.clamp(stored.object(forKey: "closedExtraHeight") as? Double ?? 0, 0...14)

        style = IslandStyle(rawValue: stored.string(forKey: "style") ?? "") ?? .black
        motion = MotionStyle(rawValue: stored.string(forKey: "motion") ?? "") ?? .smooth
        accent = AccentChoice(rawValue: stored.string(forKey: "accent") ?? "") ?? .artwork
        glassDarkness = stored.object(forKey: "glassDarkness") as? Double ?? 0.28
        glassTint = GlassTint(rawValue: stored.string(forKey: "glassTint") ?? "") ?? .none
        glassTintHex = stored.string(forKey: "glassTintHex") ?? "#6E7BFF"
        glassBorder = stored.object(forKey: "glassBorder") as? Bool ?? true
        glassWhenClosed = stored.object(forKey: "glassWhenClosed") as? Bool ?? false
        glassBlendTop = stored.object(forKey: "glassBlendTop") as? Bool ?? true
        shadowStrength = stored.object(forKey: "shadowStrength") as? Double ?? 0.5

        openOnHover = stored.object(forKey: "openOnHover") as? Bool ?? true
        hoverDelay = stored.object(forKey: "hoverDelay") as? Double ?? 0.2
        haptics = stored.object(forKey: "haptics") as? Bool ?? true
        sayHello = stored.object(forKey: "sayHello") as? Bool ?? true
        swipeGestures = stored.object(forKey: "swipeGestures") as? Bool ?? true

        // Keep the saved order, and add any tabs that are new in this version at the end.
        var order: [IslandTab] = []
        for raw in stored.stringArray(forKey: "tabOrder") ?? [] {
            if let tab = IslandTab(rawValue: raw), !order.contains(tab) {
                order.append(tab)
            }
        }
        for tab in IslandTab.allCases where !order.contains(tab) {
            order.append(tab)
        }
        tabOrder = order
        var hidden: Set<IslandTab> = []
        for raw in stored.stringArray(forKey: "hiddenTabs") ?? [] {
            if let tab = IslandTab(rawValue: raw) {
                hidden.insert(tab)
            }
        }
        hiddenTabs = hidden
        openTo = stored.string(forKey: "openTo") ?? "last"

        pet = stored.object(forKey: "pet") as? Bool ?? true
        privacyDots = stored.object(forKey: "privacyDots") as? Bool ?? true

        showArtworkInNotch = stored.object(forKey: "showArtworkInNotch") as? Bool ?? true
        showVisualizer = stored.object(forKey: "showVisualizer") as? Bool ?? true
        songAlerts = stored.object(forKey: "songAlerts") as? Bool ?? true
        showSourceBadge = stored.object(forKey: "showSourceBadge") as? Bool ?? true
        hiddenMusicApps = stored.stringArray(forKey: "hiddenMusicApps") ?? []
        seenMusicApps = stored.stringArray(forKey: "seenMusicApps") ?? []

        batteryDisplay = BatteryDisplay(rawValue: stored.string(forKey: "batteryDisplay") ?? "") ?? .onBattery
        batteryStyle = BatteryStyle(rawValue: stored.string(forKey: "batteryStyle2") ?? "") ?? .ring
        emojiPack = EmojiPack(rawValue: stored.string(forKey: "emojiPack") ?? "") ?? .moods
        batteryColorMode = BatteryColorMode(rawValue: stored.string(forKey: "batteryColorMode") ?? "") ?? .auto
        batteryColorHex = stored.string(forKey: "batteryColorHex") ?? "#4CD964"
        batteryPercentSign = stored.object(forKey: "batteryPercentSign") as? Bool ?? true
        batteryAlerts = stored.object(forKey: "batteryAlerts") as? Bool ?? true

        deviceAlerts = stored.object(forKey: "deviceAlerts") as? Bool ?? true
        badgesEnabled = stored.object(forKey: "badgesEnabled") as? Bool ?? false
        messageAlerts = stored.object(forKey: "messageAlerts") as? Bool ?? true
        calendarAlerts = stored.object(forKey: "calendarAlerts") as? Bool ?? true
        calendarLeadMinutes = stored.object(forKey: "calendarLeadMinutes") as? Int ?? 5
        showAllDayEvents = stored.object(forKey: "showAllDayEvents") as? Bool ?? true
        mirrorFlip = stored.object(forKey: "mirrorFlip") as? Bool ?? true
        mirrorShape = MirrorShape(rawValue: stored.string(forKey: "mirrorShape") ?? "") ?? .circle

        difficulty = Difficulty(rawValue: stored.string(forKey: "difficulty") ?? "") ?? .normal
        gameSounds = stored.object(forKey: "gameSounds") as? Bool ?? true
        lastGame = stored.string(forKey: "lastGame") ?? "runner"
    }

    /// The tabs to show in the open island, in the user's order. Never empty.
    var visibleTabs: [IslandTab] {
        let visible = tabOrder.filter { !hiddenTabs.contains($0) }
        return visible.isEmpty ? [.home] : visible
    }

    func setTab(_ tab: IslandTab, visible: Bool) {
        var hidden = hiddenTabs
        if visible {
            hidden.remove(tab)
        } else if visibleTabs.count > 1 || !visibleTabs.contains(tab) {
            hidden.insert(tab) // Always keep at least one tab.
        }
        hiddenTabs = hidden
    }

    func moveTab(_ tab: IslandTab, by offset: Int) {
        guard let index = tabOrder.firstIndex(of: tab) else { return }
        let target = min(max(0, index + offset), tabOrder.count - 1)
        guard target != index else { return }
        var order = tabOrder
        order.remove(at: index)
        order.insert(tab, at: target)
        tabOrder = order
    }

    func apply(_ preset: SizePreset) {
        openWidth = preset.width
        openHeight = preset.height
    }

    func resetSize() {
        apply(.standard)
        cornerRadius = 34
        wingWidth = 70
        closedExtraHeight = 0
    }

    func resetAppearance() {
        style = .black
        motion = .smooth
        accent = .artwork
        glassDarkness = 0.28
        glassTint = .none
        glassBorder = true
        glassWhenClosed = false
        glassBlendTop = true
        shadowStrength = 0.5
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }

    private static func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

extension Color {
    /// "#RRGGBB" → Color.
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") {
            text.removeFirst()
        }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    /// Color → "#RRGGBB", for saving.
    var hexString: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.white
        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
