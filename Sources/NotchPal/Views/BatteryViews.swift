// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// How the battery looks everywhere in NotchPal, following your Battery settings.
@MainActor
enum BatteryLook {
    static let green = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let yellow = Color(red: 1.0, green: 0.8, blue: 0.04)
    static let red = Color(red: 1.0, green: 0.27, blue: 0.23)

    /// The battery's colour right now.
    static func color(_ app: AppModel) -> Color {
        color(app, level: app.power.level, charging: app.power.isCharging)
    }

    /// The colour for any level, so alerts and previews match the notch.
    static func color(_ app: AppModel, level: Int, charging: Bool) -> Color {
        switch app.settings.batteryColorMode {
        case .auto:
            // Like iPhone: white, green while charging, yellow in Low Power Mode, red when low.
            if charging { return green }
            if app.power.lowPowerMode { return yellow }
            if level <= 20 { return red }
            return .white
        case .accent:
            return app.accent
        case .custom:
            return Color(hex: app.settings.batteryColorHex) ?? .green
        }
    }

    static func percentText(_ app: AppModel) -> String {
        percentText(app, level: app.power.level)
    }

    static func percentText(_ app: AppModel, level: Int) -> String {
        "\(level)" + (app.settings.batteryPercentSign ? "%" : "")
    }
}

/// Everything needed to draw the battery once. Previews and alerts make their own,
/// so they can show any style or level.
struct BatteryReading {
    var level: Int
    var charging: Bool
    var tint: Color
    var text: String
    var emoji: String
    var style: BatteryStyle

    @MainActor
    static func current(_ app: AppModel, style: BatteryStyle? = nil) -> BatteryReading {
        make(app, level: app.power.level, charging: app.power.isCharging, style: style)
    }

    @MainActor
    static func make(_ app: AppModel, level: Int, charging: Bool, style: BatteryStyle? = nil) -> BatteryReading {
        BatteryReading(
            level: level,
            charging: charging,
            tint: BatteryLook.color(app, level: level, charging: charging),
            text: BatteryLook.percentText(app, level: level),
            emoji: app.settings.emojiPack.emoji(level: level, charging: charging),
            style: style ?? app.settings.batteryStyle
        )
    }

    /// Same colours, but no charging bolt, for when a bolt is already showing nearby.
    func withoutBolt() -> BatteryReading {
        var copy = self
        copy.charging = false
        return copy
    }

    /// Ring, Classic and Emoji have a picture and a separate number.
    /// Pill has the number inside, and Number is only the number.
    var hasSeparateParts: Bool {
        style == .ring || style == .percent || style == .emoji
    }
}

/// The battery's picture in your chosen style.
struct BatteryIcon: View {
    let reading: BatteryReading
    /// About how tall the picture is, in points.
    var size: CGFloat = 14

    var body: some View {
        switch reading.style {
        case .ring:
            BatteryRing(level: reading.level, tint: reading.tint, charging: reading.charging, diameter: size)
        case .pill:
            BatteryPill(level: reading.level, tint: reading.tint, charging: reading.charging, height: size * 0.92)
        case .percent:
            BatteryGlyph(level: reading.level, tint: reading.tint, charging: reading.charging, height: size * 0.82)
        case .minimal:
            ChargingBolt(tint: reading.tint, size: size * 0.78)
                .opacity(reading.charging ? 1 : 0)
        case .emoji:
            Text(reading.emoji)
                .font(.system(size: size))
                .contentTransition(.opacity)
        }
    }
}

/// The number, like "82%".
struct BatteryNumber: View {
    let reading: BatteryReading
    var size: CGFloat = 14

    var body: some View {
        Text(reading.text)
            .font(.system(size: size * 0.86, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(reading.tint)
            .contentTransition(.numericText(value: Double(reading.level)))
            .animation(.smooth, value: reading.level)
    }
}

/// Picture and number together, as one piece.
struct BatteryBadge: View {
    let reading: BatteryReading
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: max(3, size * 0.28)) {
            switch reading.style {
            case .pill:
                BatteryIcon(reading: reading, size: size)
            case .minimal:
                if reading.charging {
                    ChargingBolt(tint: reading.tint, size: size * 0.74)
                }
                BatteryNumber(reading: reading, size: size)
            default:
                BatteryIcon(reading: reading, size: size)
                BatteryNumber(reading: reading, size: size)
            }
        }
    }
}

/// The battery in the closed notch. With Pal on the left, the whole battery sits on the right.
/// Without Pal, the picture goes left of the camera and the number right, like music does.
struct BatteryWing: View {
    enum Side {
        case leading
        case trailing
    }

    let app: AppModel
    let side: Side
    /// Use a different style, for previews.
    var style: BatteryStyle?

    var body: some View {
        let reading = BatteryReading.current(app, style: style)
        switch side {
        case .leading:
            if reading.hasSeparateParts {
                BatteryIcon(reading: reading, size: 13)
            }
        case .trailing:
            if app.settings.pet || !reading.hasSeparateParts {
                BatteryBadge(reading: reading, size: 13)
            } else {
                BatteryNumber(reading: reading, size: 14)
            }
        }
    }
}

/// A thin ring that fills up with the battery, like the battery widget on iPhone and Apple Watch.
struct BatteryRing: View {
    let level: Int
    let tint: Color
    var charging = false
    var diameter: CGFloat = 14

    var body: some View {
        let line = max(1.8, diameter * 0.15)
        let fraction = CGFloat(min(100, max(0, level))) / 100
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.2), lineWidth: line)
            Circle()
                .inset(by: line / 2)
                .trim(from: 0, to: max(0.02, fraction))
                .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: diameter * 0.44, weight: .black))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(.smooth(duration: 0.6), value: level)
    }
}

/// An iPhone-style battery with the number inside. The number flips from white to dark
/// where the battery is filled, so it's readable at any level.
struct BatteryPill: View {
    let level: Int
    let tint: Color
    var charging = false
    var height: CGFloat = 13

    var body: some View {
        let width = height * 2.05
        let shell = RoundedRectangle(cornerRadius: height * 0.34, style: .continuous)
        let fraction = CGFloat(min(100, max(0, level))) / 100
        let number = Text("\(level)")
            .font(.system(size: height * 0.7, weight: .bold, design: .rounded))
            .monospacedDigit()
        HStack(spacing: max(1, height * 0.1)) {
            ZStack {
                shell.fill(Color.white.opacity(0.26))
                number.foregroundStyle(.white)
                ZStack {
                    shell.fill(tint)
                    number.foregroundStyle(.black.opacity(0.82))
                }
                .mask(alignment: .leading) {
                    Rectangle().frame(width: width * fraction)
                }
            }
            .frame(width: width, height: height)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color.white.opacity(0.35))
                .frame(width: max(1.5, height * 0.12), height: height * 0.36)
            if charging {
                ChargingBolt(tint: tint, size: height * 0.78)
            }
        }
        .animation(.smooth(duration: 0.6), value: level)
    }
}

/// A small outlined battery, filled to the level, like the one in the menu bar.
struct BatteryGlyph: View {
    let level: Int
    let tint: Color
    var charging = false
    var height: CGFloat = 12

    var body: some View {
        let width = height * 2.1
        let line = max(1, height * 0.09)
        let inset = line + max(1, height * 0.1)
        let fraction = CGFloat(min(100, max(0, level))) / 100
        HStack(spacing: max(1, height * 0.08)) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height * 0.3, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.4), lineWidth: line)
                RoundedRectangle(cornerRadius: height * 0.16, style: .continuous)
                    .fill(tint)
                    .frame(width: max(height * 0.2, (width - inset * 2) * fraction))
                    .padding(inset)
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: height * 0.7, weight: .black))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.7), radius: 0.8)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: width, height: height)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color.white.opacity(0.4))
                .frame(width: max(1.5, height * 0.13), height: height * 0.38)
        }
        .animation(.smooth(duration: 0.6), value: level)
    }
}

struct ChargingBolt: View {
    let tint: Color
    var size: CGFloat = 11

    var body: some View {
        Image(systemName: "bolt.fill")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(tint)
    }
}

/// The small battery card on the Music tab.
struct BatteryCard: View {
    let app: AppModel
    var compact = false
    var scale: CGFloat = 1

    var body: some View {
        let power = app.power
        VStack(spacing: 3 * scale) {
            BatteryBadge(reading: BatteryReading.current(app), size: (compact ? 15 : 18) * max(0.85, scale))
            if !compact {
                Text(power.timeDescription)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: (compact ? 12 : 16) * scale, style: .continuous).fill(Color.white.opacity(0.07)))
        .help(power.timeDescription)
    }
}
