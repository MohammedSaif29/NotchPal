// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

/// The island's edge without its straight top, which sits at the very top of the screen.
/// The glow traces this line, flares included.
struct NotchRim: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.width / 4)
        let bottom = max(0, min(bottomRadius, rect.height - top, (rect.width - top * 2) / 2))

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY + top),
                          control: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
                          control: CGPoint(x: rect.minX + top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
                          control: CGPoint(x: rect.maxX - top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.maxX - top, y: rect.minY))
        return path
    }
}

/// The light around the island. Sits behind it, so only the outside of the glow shows.
struct IslandGlow: View {
    let app: AppModel
    let content: IslandContent
    let size: CGSize
    let topRadius: CGFloat
    let bottomRadius: CGFloat

    var body: some View {
        let engine = app.glow
        let _ = engine.heartbeat
        let glow = size.height >= 4 ? engine.current(app, content: content) : nil
        let style = app.settings.glowStyle
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || app.power.lowPowerMode
        let interval = GlowLayers.frameInterval(glow, style: style, still: still)

        ZStack(alignment: .top) {
            if let glow {
                TimelineView(.animation(minimumInterval: interval ?? 1, paused: interval == nil)) { context in
                    // Asked again each frame, so a timer's colour keeps moving from green to red.
                    if let live = engine.current(app, content: content, now: context.date) {
                        GlowLayers(glow: live, style: style, brightness: app.settings.glowBrightness,
                                   size: size, topRadius: topRadius, bottomRadius: bottomRadius,
                                   time: interval == nil ? nil : context.date.timeIntervalSinceReferenceDate)
                    }
                }
                .id(glow.key)
                .transition(.opacity)
            }
        }
        .frame(width: size.width, height: max(size.height, 1), alignment: .top)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 1.1), value: glow?.key)
    }
}

/// The glow itself, in one of four styles. Used on the notch and in Settings' preview.
struct GlowLayers: View {
    let glow: Glow
    let style: GlowStyle
    let brightness: Double
    let size: CGSize
    let topRadius: CGFloat
    let bottomRadius: CGFloat
    /// Seconds, to drive the motion. Nil keeps it still.
    let time: Double?

    var body: some View {
        let level = min(1, Self.level(glow.rhythm, time) * glow.strength * brightness)
        // Aurora drifts only while something is happening; at rest every style holds still.
        let flowing = time != nil && (glow.rhythm == .flow || (style == .aurora && glow.rhythm != .still))
        let phase: Double? = flowing ? Self.phase(time ?? 0, period: glow.rhythm == .flow ? 2.4 : 7) : nil
        let paint = Self.edgePaint(glow.colors, phase: phase)
        let rim = NotchRim(topRadius: topRadius, bottomRadius: bottomRadius)

        ZStack(alignment: .top) {
            switch style {
            case .halo:
                rim.stroke(paint, lineWidth: 14).blur(radius: 18).opacity(level)
                rim.stroke(paint, lineWidth: 4).blur(radius: 5).opacity(level * 0.9)
            case .neon:
                rim.stroke(paint, lineWidth: 9).blur(radius: 11).opacity(level * 0.8)
                rim.stroke(paint, lineWidth: 2.6).blur(radius: 0.6).opacity(min(1, level * 1.15))
            case .aurora:
                rim.stroke(paint, lineWidth: 24).blur(radius: 28).opacity(level * 0.9)
                rim.stroke(paint, lineWidth: 7).blur(radius: 9).opacity(level * 0.75)
            case .ripple:
                rim.stroke(paint, lineWidth: 6).blur(radius: 9).opacity(level * 0.75)
                if let time, glow.rhythm != .still {
                    let period = Self.ripplePeriod(glow.rhythm)
                    ForEach(0..<3, id: \.self) { ring in
                        let progress = Self.phase(time + Double(ring) * period / 3, period: period)
                        let spread = CGFloat(progress) * 26
                        NotchRim(topRadius: topRadius, bottomRadius: bottomRadius + spread)
                            .stroke(paint, lineWidth: 2)
                            .frame(width: size.width + spread * 2, height: size.height + spread)
                            .blur(radius: 0.8 + CGFloat(progress) * 2.5)
                            .opacity((1 - progress) * level)
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    /// How often to redraw, or nil when the glow doesn't move.
    static func frameInterval(_ glow: Glow?, style: GlowStyle, still: Bool) -> Double? {
        guard let glow, !still else { return nil }
        switch glow.rhythm {
        case .still: return glow.updateEvery // Nil: drawn once, no battery cost.
        case .breathe: return 1.0 / 20
        case .groove, .urgent, .flow: return 1.0 / 30
        }
    }

    /// How bright the glow is at this moment, 0…1.
    static func level(_ rhythm: GlowRhythm, _ time: Double?) -> Double {
        guard let t = time else { return 0.88 }
        switch rhythm {
        case .still:
            return 0.88
        case .breathe:
            return 0.8 + 0.2 * sin(t * 2 * .pi / 3.6)
        case .groove:
            // A pump on every beat (about 112 a minute) over a slow swell.
            let beat = pow(abs(sin(t * .pi * 112 / 60)), 5)
            return 0.72 + 0.22 * beat + 0.06 * sin(t * 2 * .pi / 6.5)
        case .urgent:
            return 0.55 + 0.45 * (0.5 + 0.5 * sin(t * 2 * .pi * 1.3))
        case .flow:
            return 0.92 + 0.08 * sin(t * 2 * .pi / 2.5)
        }
    }

    static func ripplePeriod(_ rhythm: GlowRhythm) -> Double {
        switch rhythm {
        case .groove: return 1.6
        case .urgent: return 1.1
        case .flow: return 2
        case .breathe, .still: return 3
        }
    }

    /// 0…1, looping every `period` seconds.
    static func phase(_ time: Double, period: Double) -> Double {
        let value = (time / period).truncatingRemainder(dividingBy: 1)
        return value < 0 ? value + 1 : value
    }

    /// The colours left to right along the edge. While flowing, the colours repeat twice over
    /// a gradient twice as wide and slide along it, so the loop has no seam.
    static func edgePaint(_ colors: [Color], phase: Double?) -> LinearGradient {
        let colors = colors.isEmpty ? [GlowColors.white] : colors
        guard let phase else {
            return LinearGradient(colors: colors.count == 1 ? colors + colors : colors,
                                  startPoint: .leading, endPoint: .trailing)
        }
        let loop = colors + [colors[0]]
        var stops: [Gradient.Stop] = []
        for lap in 0..<2 {
            for (index, color) in loop.enumerated() where !(lap == 0 && index == loop.count - 1) {
                let location = (Double(lap) + Double(index) / Double(loop.count - 1)) / 2
                stops.append(Gradient.Stop(color: color, location: location))
            }
        }
        return LinearGradient(stops: stops,
                              startPoint: UnitPoint(x: -phase, y: 0.5),
                              endPoint: UnitPoint(x: 2 - phase, y: 0.5))
    }
}
