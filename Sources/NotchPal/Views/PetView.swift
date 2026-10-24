// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// What the notch pet is feeling, based on what your Mac is doing.
enum PetMood: Equatable {
    case idle
    case dancing     // music is playing
    case munching    // charging: it's eating electricity
    case worried     // battery is low
    case sleepy      // it's late at night
    case curious     // you're hovering over it
    case focused     // a timer is running

    @MainActor
    static func current(_ app: AppModel, now: Date) -> PetMood {
        let power = app.power
        if app.nowPlaying.isPlaying { return .dancing }
        if power.hasBattery && !power.onPower && power.level <= 15 { return .worried }
        if app.state.mode == .peek { return .curious }
        if power.hasBattery && power.isCharging && power.level < 100 { return .munching }
        if app.timer.isActive { return .focused }
        let hour = Calendar.current.component(.hour, from: now)
        if hour < 6 { return .sleepy }
        return .idle
    }
}

/// Pal, the little creature that lives in your notch.
struct NotchPet: View {
    let app: AppModel

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
            let mood = PetMood.current(app, now: context.date)
            let tint = app.accent
            Canvas { graphics, size in
                PetArt.draw(mood: mood, time: context.date.timeIntervalSinceReferenceDate,
                            tint: tint, in: &graphics, size: size)
            }
        }
        .frame(width: 34, height: 26)
        .help("Pal lives here. It dances to music, eats while charging and naps late at night.")
    }
}

enum PetArt {
    static func draw(mood: PetMood, time t: Double, tint: Color, in context: inout GraphicsContext, size: CGSize) {
        // Body movement for each mood.
        var bob: CGFloat = 0
        var squash: CGFloat = 1
        switch mood {
        case .dancing:
            bob = CGFloat(sin(t * 9)) * 2.2
            squash = 1 + CGFloat(sin(t * 18)) * 0.07
        case .munching:
            bob = -CGFloat(abs(sin(t * 6))) * 1.4
        case .curious:
            bob = -1.5 + CGFloat(sin(t * 4)) * 0.5
        case .sleepy:
            squash = 1 + CGFloat(sin(t * 1.6)) * 0.05
        case .worried:
            bob = CGFloat(sin(t * 30)) * 0.4 // shivering
        case .idle, .focused:
            squash = 1 + CGFloat(sin(t * 2.2)) * 0.025
        }

        let width = 18 * (2 - squash)
        let height = 15 * squash
        let body = CGRect(x: (size.width - width) / 2, y: size.height - height - 2 + bob, width: width, height: height)
        context.fill(Path(roundedRect: body, cornerRadius: 6), with: .color(.white))

        // Eyes
        let eyeY = body.minY + height * 0.42
        var left = CGPoint(x: body.minX + width * 0.34, y: eyeY)
        var right = CGPoint(x: body.minX + width * 0.66, y: eyeY)
        let blinking = t.truncatingRemainder(dividingBy: 4.3) < 0.14

        switch mood {
        case .sleepy:
            line(from: left, width: 3.4, in: &context)
            line(from: right, width: 3.4, in: &context)
            floatingText("z", phase: t * 0.5, from: CGPoint(x: body.maxX + 2, y: body.minY + 2),
                         color: .white, in: &context)
        case .dancing, .munching:
            chevron(at: left, in: &context)
            chevron(at: right, in: &context)
        case .worried:
            dot(at: left, scale: 0.8, in: &context)
            dot(at: right, scale: 0.8, in: &context)
            let drop = CGRect(x: body.maxX - 1, y: body.minY + 1, width: 2.6, height: 3.8)
            context.fill(Path(ellipseIn: drop), with: .color(Color(red: 0.45, green: 0.75, blue: 1)))
        case .curious:
            left.y -= 1
            right.y -= 1
            left.x += 1
            right.x += 1
            dot(at: left, scale: 1.15, in: &context)
            dot(at: right, scale: 1.15, in: &context)
        case .focused:
            line(from: left, width: 3.4, in: &context, weight: 1.8)
            line(from: right, width: 3.4, in: &context, weight: 1.8)
        case .idle:
            if blinking {
                line(from: left, width: 3.2, in: &context)
                line(from: right, width: 3.2, in: &context)
            } else {
                dot(at: left, scale: 1, in: &context)
                dot(at: right, scale: 1, in: &context)
            }
        }

        // Mouth and extras
        let mouthCenter = CGPoint(x: body.midX, y: body.minY + height * 0.72)
        switch mood {
        case .munching:
            let open = 0.8 + CGFloat(abs(sin(t * 10))) * 2
            context.fill(Path(ellipseIn: CGRect(x: mouthCenter.x - 1.6, y: mouthCenter.y - open / 2, width: 3.2, height: open)),
                         with: .color(.black))
            floatingText("⚡", phase: t * 0.7, from: CGPoint(x: body.minX - 4, y: body.minY + 3),
                         color: .yellow, in: &context)
        case .dancing:
            var smile = Path()
            smile.move(to: CGPoint(x: mouthCenter.x - 2, y: mouthCenter.y - 0.5))
            smile.addQuadCurve(to: CGPoint(x: mouthCenter.x + 2, y: mouthCenter.y - 0.5),
                               control: CGPoint(x: mouthCenter.x, y: mouthCenter.y + 2))
            context.stroke(smile, with: .color(.black), lineWidth: 1)
            floatingText("♪", phase: t * 0.8, from: CGPoint(x: body.maxX + 3, y: body.minY + 4),
                         color: tint, in: &context)
        case .worried:
            var wobble = Path()
            wobble.move(to: CGPoint(x: mouthCenter.x - 2, y: mouthCenter.y + 0.5))
            wobble.addLine(to: CGPoint(x: mouthCenter.x - 0.7, y: mouthCenter.y - 0.5))
            wobble.addLine(to: CGPoint(x: mouthCenter.x + 0.7, y: mouthCenter.y + 0.5))
            wobble.addLine(to: CGPoint(x: mouthCenter.x + 2, y: mouthCenter.y - 0.5))
            context.stroke(wobble, with: .color(.black), lineWidth: 0.9)
        default:
            break
        }
    }

    private static func dot(at point: CGPoint, scale: CGFloat, in context: inout GraphicsContext) {
        let rect = CGRect(x: point.x - 1.5 * scale, y: point.y - 1.8 * scale, width: 3 * scale, height: 3.6 * scale)
        context.fill(Path(ellipseIn: rect), with: .color(.black))
    }

    private static func line(from point: CGPoint, width: CGFloat, in context: inout GraphicsContext, weight: CGFloat = 1.2) {
        var path = Path()
        path.move(to: CGPoint(x: point.x - width / 2, y: point.y))
        path.addLine(to: CGPoint(x: point.x + width / 2, y: point.y))
        context.stroke(path, with: .color(.black), lineWidth: weight)
    }

    /// A happy "^" eye.
    private static func chevron(at point: CGPoint, in context: inout GraphicsContext) {
        var path = Path()
        path.move(to: CGPoint(x: point.x - 1.8, y: point.y + 1))
        path.addLine(to: CGPoint(x: point.x, y: point.y - 1))
        path.addLine(to: CGPoint(x: point.x + 1.8, y: point.y + 1))
        context.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
    }

    /// Text that drifts up and fades, like "z" or a music note.
    private static func floatingText(_ text: String, phase: Double, from origin: CGPoint, color: Color,
                                     in context: inout GraphicsContext) {
        let progress = phase - floor(phase)
        let label = Text(text)
            .font(.system(size: 7, weight: .bold))
            .foregroundColor(color.opacity(1 - progress))
        context.draw(label, at: CGPoint(x: origin.x + CGFloat(progress) * 2, y: origin.y - CGFloat(progress) * 7))
    }
}
