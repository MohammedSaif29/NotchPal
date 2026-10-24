// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import Observation

/// Notch Runner: the Pal runs along the bottom of the island and jumps over blocks.
/// It speeds up the longer you survive. Down arrow drops you faster mid-jump.
@MainActor
@Observable
final class RunnerGame: NotchGame {
    private(set) var phase: GamePhase = .ready
    private(set) var best: Int

    private let settings: SettingsStore
    @ObservationIgnored private var tuning: Tuning
    @ObservationIgnored private var height: CGFloat = 0
    @ObservationIgnored private var velocity: CGFloat = 0
    @ObservationIgnored private var blocks: [Block] = []
    @ObservationIgnored private var speed: CGFloat = 0
    @ObservationIgnored private var distance: CGFloat = 0
    @ObservationIgnored private var nextBlockIn: Double = 0.9
    @ObservationIgnored private var groundShift: CGFloat = 0
    @ObservationIgnored private var stars: [CGPoint] = []
    @ObservationIgnored private var lastFrame: Date?
    @ObservationIgnored private var crashed = false
    @ObservationIgnored private var newBest = false

    private static let bestKey = "runner.best"
    private static let gravity: CGFloat = 2200
    private static let jumpVelocity: CGFloat = 560
    private static let palSize: CGFloat = 18
    private static let palX: CGFloat = 48
    private static let groundInset: CGFloat = 14

    private struct Block {
        var x: CGFloat
        var width: CGFloat
        var height: CGFloat
    }

    private struct Tuning {
        var startSpeed: CGFloat
        var maxSpeed: CGFloat
        var gain: CGFloat
        var gaps: ClosedRange<Double>
        var heights: ClosedRange<CGFloat>

        static func make(_ difficulty: Difficulty) -> Tuning {
            switch difficulty {
            case .easy:
                Tuning(startSpeed: 220, maxSpeed: 460, gain: 4, gaps: 0.95...1.7, heights: 12...24)
            case .normal:
                Tuning(startSpeed: 270, maxSpeed: 600, gain: 7, gaps: 0.7...1.35, heights: 14...30)
            case .hard:
                Tuning(startSpeed: 330, maxSpeed: 760, gain: 10, gaps: 0.55...1.1, heights: 16...36)
            }
        }
    }

    init(settings: SettingsStore) {
        self.settings = settings
        best = GameArt.loadBest(Self.bestKey)
        tuning = Tuning.make(settings.difficulty)
        speed = tuning.startSpeed
    }

    private var score: Int { Int(distance / 12) }

    // MARK: Input

    func handle(_ input: GameInput) {
        switch input {
        case .action, .up:
            jump()
        case .down:
            if phase == .running && height > 0 {
                velocity = min(velocity, -Self.jumpVelocity)
            }
        case .left, .right:
            break
        }
    }

    private func jump() {
        switch phase {
        case .ready, .over:
            reset()
            phase = .running
        case .paused:
            lastFrame = nil
            phase = .running
        case .running:
            if height <= 0.5 {
                velocity = Self.jumpVelocity
                GameArt.sound("Tink", volume: 0.15, enabled: settings.gameSounds)
            }
        }
    }

    func pause() {
        if phase == .running { phase = .paused }
    }

    func reset() {
        tuning = Tuning.make(settings.difficulty)
        height = 0
        velocity = 0
        blocks = []
        speed = tuning.startSpeed
        distance = 0
        nextBlockIn = 0.9
        lastFrame = nil
        crashed = false
        newBest = false
        if phase != .ready { phase = .ready }
    }

    func clearBest() {
        best = 0
        GameArt.saveBest(0, Self.bestKey)
    }

    // MARK: Simulation

    func step(to now: Date, size: CGSize) {
        if stars.isEmpty {
            stars = (0..<16).map { _ in
                CGPoint(x: .random(in: 0...max(1, size.width)), y: .random(in: 4...max(5, size.height * 0.55)))
            }
        }
        guard phase == .running, !crashed else {
            lastFrame = now
            return
        }
        let dt = CGFloat(min(now.timeIntervalSince(lastFrame ?? now), 1.0 / 30.0))
        lastFrame = now

        // The Pal
        velocity -= Self.gravity * dt
        height = max(0, height + velocity * dt)
        if height == 0 && velocity < 0 { velocity = 0 }

        // The world
        speed = min(tuning.maxSpeed, speed + tuning.gain * dt)
        distance += speed * dt
        groundShift = (groundShift + speed * dt).truncatingRemainder(dividingBy: 24)
        for index in blocks.indices { blocks[index].x -= speed * dt }
        blocks.removeAll { $0.x + $0.width < -10 }
        for index in stars.indices {
            stars[index].x -= speed * 0.06 * dt
            if stars[index].x < 0 { stars[index].x += size.width }
        }

        nextBlockIn -= Double(dt)
        if nextBlockIn <= 0 {
            blocks.append(Block(x: size.width + 10,
                                width: .random(in: 10...20),
                                height: .random(in: tuning.heights)))
            // On hard, sometimes a double block right behind.
            if settings.difficulty == .hard && Int.random(in: 0..<4) == 0 {
                blocks.append(Block(x: size.width + 34, width: 12, height: .random(in: tuning.heights)))
            }
            nextBlockIn = .random(in: tuning.gaps)
        }

        // Hit test, slightly forgiving so near misses feel fair.
        let ground = size.height - Self.groundInset
        let pal = CGRect(x: Self.palX, y: ground - Self.palSize - height,
                         width: Self.palSize, height: Self.palSize).insetBy(dx: 3, dy: 3)
        for block in blocks {
            let rect = CGRect(x: block.x, y: ground - block.height, width: block.width, height: block.height)
            if rect.intersects(pal) {
                crash()
                break
            }
        }
    }

    private func crash() {
        crashed = true
        let finalScore = score
        GameArt.sound("Basso", volume: 0.25, enabled: settings.gameSounds)
        // This runs while SwiftUI is drawing, so change visible state on the next turn.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if finalScore > self.best {
                    self.best = finalScore
                    self.newBest = true
                    GameArt.saveBest(finalScore, Self.bestKey)
                }
                self.phase = .over
            }
        }
    }

    // MARK: Drawing

    func draw(in context: inout GraphicsContext, size: CGSize) {
        let ground = size.height - Self.groundInset

        for star in stars {
            context.fill(Path(ellipseIn: CGRect(x: star.x, y: star.y, width: 1.6, height: 1.6)),
                         with: .color(.white.opacity(0.35)))
        }

        var dashes = Path()
        var x = -groundShift
        while x < size.width {
            dashes.addRect(CGRect(x: x, y: ground + 2, width: 12, height: 1.5))
            x += 24
        }
        context.fill(dashes, with: .color(.white.opacity(0.25)))

        for block in blocks {
            let rect = CGRect(x: block.x, y: ground - block.height, width: block.width, height: block.height)
            context.fill(Path(roundedRect: rect, cornerRadius: 4),
                         with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.62, blue: 0.3),
                                                                 Color(red: 0.95, green: 0.35, blue: 0.25)]),
                                               startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                               endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        }

        // The Pal: a white blob with two eyes, stretched a bit mid-jump.
        let stretch: CGFloat = height > 0 ? 1.12 : 1
        let palHeight = Self.palSize * stretch
        let pal = CGRect(x: Self.palX, y: ground - palHeight - height, width: Self.palSize, height: palHeight)
        context.fill(Path(roundedRect: pal, cornerRadius: 6), with: .color(.white))

        let eyeY = pal.minY + pal.height * 0.38
        for eyeX in [pal.minX + 9, pal.minX + 13.5] {
            if phase == .over {
                var cross = Path()
                cross.move(to: CGPoint(x: eyeX - 1.6, y: eyeY - 1.6))
                cross.addLine(to: CGPoint(x: eyeX + 1.6, y: eyeY + 1.6))
                cross.move(to: CGPoint(x: eyeX + 1.6, y: eyeY - 1.6))
                cross.addLine(to: CGPoint(x: eyeX - 1.6, y: eyeY + 1.6))
                context.stroke(cross, with: .color(.black), lineWidth: 1.2)
            } else {
                context.fill(Path(ellipseIn: CGRect(x: eyeX - 1.6, y: eyeY - 1.6, width: 3.2, height: 3.2)),
                             with: .color(.black))
            }
        }

        GameArt.scoreboard("\(score)   HI \(best)", in: &context, size: size)
        GameArt.message(message, in: &context, size: size)
    }

    private var message: String? {
        switch phase {
        case .ready: "Space or click to run"
        case .paused: "Paused · click to keep going"
        case .over: newBest ? "New best: \(score)! Click to go again" : "Ouch! \(score) points · click to retry"
        case .running: nil
        }
    }
}
