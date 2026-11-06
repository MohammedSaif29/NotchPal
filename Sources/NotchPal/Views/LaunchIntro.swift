// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// The opening animation, drawn around the Mac's real notch: two sparks start at its top
/// corners, trace its edge and meet in the middle, then a flash, a streak of light, a burst
/// of coloured sparks, and the glow blooms and settles.
struct LaunchIntro: View {
    let start: Date
    let notch: NotchGeometry

    static let duration: TimeInterval = 2.9
    /// Room around the notch for the streak and the sparks.
    static let canvas = CGSize(width: 1000, height: 240)

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSince(start)
            Canvas { graphics, size in
                Self.draw(&graphics, size: size, time: time, notch: notch)
            }
        }
        .frame(width: Self.canvas.width, height: Self.canvas.height)
        .allowsHitTesting(false)
    }

    private static let palette: [Color] = [
        GlowColors.green, GlowColors.cyan, GlowColors.purple, GlowColors.pink, GlowColors.orange,
    ]

    // MARK: Drawing

    private static func draw(_ graphics: inout GraphicsContext, size: CGSize, time t: Double, notch: NotchGeometry) {
        let topRadius: CGFloat = 6
        let bottomRadius: CGFloat = 10
        let width = notch.width + topRadius * 2
        // One point outside the notch's edge, so the line sits just outside the black and is visible.
        let rect = CGRect(x: (size.width - width) / 2 - 1, y: 0, width: width + 2, height: max(notch.height, 18) + 1)
        let left = half(rect, top: topRadius, bottom: bottomRadius, leftSide: true)
        let right = half(rect, top: topRadius, bottom: bottomRadius, leftSide: false)
        let rim = NotchRim(topRadius: topRadius, bottomRadius: bottomRadius).path(in: rect)
        let meet = CGPoint(x: rect.midX, y: rect.maxY)

        // 1. Two sparks trace the edge from the top corners to the middle, drawing a thin line.
        let trace = CGFloat(easeInOut(clamp((t - 0.2) / 0.85)))
        let lineFade = 1 - clamp((t - 1.35) / 0.6)
        if trace > 0.001 && lineFade > 0 {
            for side in [left, right] {
                let drawn = side.trimmedPath(from: 0, to: trace)
                graphics.drawLayer { layer in
                    layer.addFilter(.blur(radius: 3))
                    layer.stroke(drawn, with: .color(.white.opacity(0.4 * lineFade)), lineWidth: 4)
                }
                graphics.stroke(drawn, with: .color(.white.opacity(0.92 * lineFade)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        }

        // 2. The sparks themselves, each with a short bright tail.
        if t > 0.12 && t < 1.12 {
            let appear = clamp((t - 0.12) / 0.15) * (1 - clamp((t - 1.02) / 0.1))
            for side in [left, right] {
                let tail = side.trimmedPath(from: max(0, trace - 0.16), to: max(trace, 0.001))
                let head = side.trimmedPath(from: 0, to: max(trace, 0.001)).currentPoint ?? meet
                graphics.drawLayer { layer in
                    layer.addFilter(.blur(radius: 1.5))
                    layer.stroke(tail, with: .color(.white.opacity(appear)), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                }
                glowDot(&graphics, at: head, opacity: appear)
            }
        }

        let burst = t - 1.05
        // 3. They meet: a flash, and a streak of light across the screen.
        if burst > 0 && burst < 0.85 {
            let k = burst / 0.85
            let radius = CGFloat(8 + 46 * easeOut(k))
            graphics.drawLayer { layer in
                layer.addFilter(.blur(radius: 14))
                layer.fill(Path(ellipseIn: CGRect(x: meet.x - radius, y: meet.y - radius * 0.6, width: radius * 2, height: radius * 1.2)),
                           with: .color(.white.opacity(0.9 * (1 - k))))
            }
            let grow = CGFloat(easeOut(clamp(burst / 0.35)))
            let streakAlpha = burst < 0.3 ? 1 : 1 - clamp((burst - 0.3) / 0.5)
            let streakWidth = size.width * grow
            let streak = CGRect(x: meet.x - streakWidth / 2, y: meet.y - 0.8, width: streakWidth, height: 1.6)
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [.white.opacity(0), .white.opacity(streakAlpha), .white.opacity(0)]),
                startPoint: CGPoint(x: streak.minX, y: meet.y), endPoint: CGPoint(x: streak.maxX, y: meet.y))
            graphics.drawLayer { layer in
                layer.addFilter(.blur(radius: 3))
                layer.fill(Path(streak.insetBy(dx: 0, dy: -2)), with: shading)
            }
            graphics.fill(Path(streak), with: shading)
        }

        // 4. The glow blooms in colour around the notch, then fades into the normal glow.
        let bloom = clamp((t - 1.15) / 0.45) * (1 - clamp((t - 2.25) / 0.6))
        if bloom > 0 {
            let colors = GraphicsContext.Shading.linearGradient(
                Gradient(colors: palette),
                startPoint: CGPoint(x: rect.minX, y: 0), endPoint: CGPoint(x: rect.maxX, y: 0))
            graphics.drawLayer { layer in
                layer.addFilter(.blur(radius: 16))
                layer.opacity = bloom
                layer.stroke(rim, with: colors, lineWidth: 14)
            }
            graphics.drawLayer { layer in
                layer.addFilter(.blur(radius: 3))
                layer.opacity = bloom * 0.9
                layer.stroke(rim, with: colors, lineWidth: 3)
            }
        }

        // 5. Coloured sparks burst out and fall from where the lines met.
        if burst > 0.02 && burst < 1.05 {
            for index in 0..<22 {
                let life = 0.55 + 0.45 * random(index, 3)
                let age = burst - 0.02 - 0.06 * random(index, 4)
                guard age > 0 && age < life else { continue }
                let angle = (15 + 150 * random(index, 1)) * Double.pi / 180 // Below the line, from right to left.
                let speed = 70 + 120 * random(index, 2)
                let dx = CGFloat(cos(angle))
                let dy = CGFloat(sin(angle))
                let travel = CGFloat(speed * age * (1 - 0.35 * age))
                let fall = CGFloat(60 * age * age)
                let point = CGPoint(x: meet.x + dx * travel, y: meet.y + dy * travel + fall)
                let tail = CGPoint(x: point.x - dx * 7, y: point.y - dy * 7 - CGFloat(2 * age))
                var spark = Path()
                spark.move(to: tail)
                spark.addLine(to: point)
                let color = palette[index % palette.count]
                let alpha = 1 - age / life
                graphics.stroke(spark, with: .color(color.opacity(alpha)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
        }
    }

    /// The left or right half of the notch's edge: from its top corner, down the side, to the middle.
    private static func half(_ rect: CGRect, top: CGFloat, bottom: CGFloat, leftSide: Bool) -> Path {
        let topR = min(top, rect.width / 4)
        let bottomR = max(0, min(bottom, rect.height - topR, (rect.width - topR * 2) / 2))
        var path = Path()
        if leftSide {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.minX + topR, y: rect.minY + topR),
                              control: CGPoint(x: rect.minX + topR, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + topR, y: rect.maxY - bottomR))
            path.addQuadCurve(to: CGPoint(x: rect.minX + topR + bottomR, y: rect.maxY),
                              control: CGPoint(x: rect.minX + topR, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - topR, y: rect.minY + topR),
                              control: CGPoint(x: rect.maxX - topR, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.maxY - bottomR))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - topR - bottomR, y: rect.maxY),
                              control: CGPoint(x: rect.maxX - topR, y: rect.maxY))
        }
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }

    private static func glowDot(_ graphics: inout GraphicsContext, at point: CGPoint, opacity: Double) {
        graphics.drawLayer { layer in
            layer.addFilter(.blur(radius: 6))
            layer.fill(Path(ellipseIn: CGRect(x: point.x - 11, y: point.y - 11, width: 22, height: 22)),
                       with: .color(.white.opacity(0.55 * opacity)))
        }
        graphics.fill(Path(ellipseIn: CGRect(x: point.x - 2.6, y: point.y - 2.6, width: 5.2, height: 5.2)),
                      with: .color(.white.opacity(opacity)))
    }

    // MARK: Helpers

    private static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }

    private static func easeInOut(_ x: Double) -> Double {
        x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }

    private static func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }

    /// The same "random" number every time for a spark, so the burst looks the same each frame.
    private static func random(_ index: Int, _ salt: Int) -> Double {
        let value = sin(Double(index) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return value - floor(value)
    }
}
