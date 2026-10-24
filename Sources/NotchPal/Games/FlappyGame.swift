// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import Observation

/// Flappy Notch: keep the bird in the air and slip through the gaps.
@MainActor
@Observable
final class FlappyGame: NotchGame {
    private(set) var phase: GamePhase = .ready
    private(set) var best: Int

    private let settings: SettingsStore
    @ObservationIgnored private var tuning: Tuning
    @ObservationIgnored private var birdY: CGFloat = -1
    @ObservationIgnored private var velocity: CGFloat = 0
    @ObservationIgnored private var pipes: [Pipe] = []
    @ObservationIgnored private var nextPipeIn: Double = 0.5
    @ObservationIgnored private var score = 0
    @ObservationIgnored private var lastFrame: Date?
    @ObservationIgnored private var lastSize = CGSize(width: 400, height: 120)
    @ObservationIgnored private var crashed = false
    @ObservationIgnored private var newBest = false
    @ObservationIgnored private var bob: Double = 0

    private static let bestKey = "flappy.best"
    private static let birdX: CGFloat = 72
    private static let radius: CGFloat = 7
    private static let pipeWidth: CGFloat = 26

    private struct Pipe {
        var x: CGFloat
        var gapCenter: CGFloat
        var passed = false
    }

    private struct Tuning {
        var gapRatio: CGFloat
        var speed: CGFloat
        var interval: Double

        static func make(_ difficulty: Difficulty) -> Tuning {
            switch difficulty {
            case .easy: Tuning(gapRatio: 0.56, speed: 115, interval: 1.6)
            case .normal: Tuning(gapRatio: 0.47, speed: 145, interval: 1.35)
            case .hard: Tuning(gapRatio: 0.39, speed: 180, interval: 1.15)
            }
        }
    }

    init(settings: SettingsStore) {
        self.settings = settings
        best = GameArt.loadBest(Self.bestKey)
        tuning = Tuning.make(settings.difficulty)
    }

    // MARK: Input

    func handle(_ input: GameInput) {
        if input == .action || input == .up {
            flap()
        }
    }

    private func flap() {
        switch phase {
        case .ready, .over:
            reset()
            phase = .running
            velocity = -lastSize.height * 2.6
        case .paused:
            lastFrame = nil
            phase = .running
        case .running:
            velocity = -lastSize.height * 2.6
            GameArt.sound("Pop", volume: 0.12, enabled: settings.gameSounds)
        }
    }

    func pause() {
        if phase == .running { phase = .paused }
    }

    func reset() {
        tuning = Tuning.make(settings.difficulty)
        birdY = lastSize.height / 2
        velocity = 0
        pipes = []
        nextPipeIn = 0.5
        score = 0
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
        lastSize = size
        if birdY < 0 { birdY = size.height / 2 }
        guard phase == .running, !crashed else {
            lastFrame = now
            return
        }
        let dt = CGFloat(min(now.timeIntervalSince(lastFrame ?? now), 1.0 / 30.0))
        lastFrame = now

        // Gravity scales with the island's height so the game feels the same at every size.
        velocity += size.height * 9 * dt
        birdY += velocity * dt
        if birdY < Self.radius {
            birdY = Self.radius
            velocity = max(0, velocity)
        }
        if birdY > size.height - Self.radius {
            crash()
            return
        }

        for index in pipes.indices {
            pipes[index].x -= tuning.speed * dt
            if !pipes[index].passed && pipes[index].x + Self.pipeWidth < Self.birdX - Self.radius {
                pipes[index].passed = true
                score += 1
                GameArt.sound("Tink", volume: 0.18, enabled: settings.gameSounds)
            }
        }
        pipes.removeAll { $0.x < -Self.pipeWidth - 4 }

        let gap = size.height * tuning.gapRatio
        nextPipeIn -= Double(dt)
        if nextPipeIn <= 0 {
            let margin = gap / 2 + 8
            let center = CGFloat.random(in: margin...max(margin, size.height - margin))
            pipes.append(Pipe(x: size.width + 10, gapCenter: center))
            nextPipeIn = tuning.interval
        }

        for pipe in pipes where pipe.x < Self.birdX + Self.radius && pipe.x + Self.pipeWidth > Self.birdX - Self.radius {
            let top = pipe.gapCenter - gap / 2
            let bottom = pipe.gapCenter + gap / 2
            if birdY - Self.radius + 2 < top || birdY + Self.radius - 2 > bottom {
                crash()
                return
            }
        }
    }

    private func crash() {
        crashed = true
        let finalScore = score
        GameArt.sound("Basso", volume: 0.25, enabled: settings.gameSounds)
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
        let gap = size.height * tuning.gapRatio
        let pipeColor = Color(red: 0.35, green: 0.85, blue: 0.45)
        let lipColor = Color(red: 0.25, green: 0.7, blue: 0.35)

        for pipe in pipes {
            let top = pipe.gapCenter - gap / 2
            let bottom = pipe.gapCenter + gap / 2
            let upper = CGRect(x: pipe.x, y: -6, width: Self.pipeWidth, height: top + 6)
            let lower = CGRect(x: pipe.x, y: bottom, width: Self.pipeWidth, height: size.height - bottom + 6)
            context.fill(Path(roundedRect: upper, cornerRadius: 5), with: .color(pipeColor))
            context.fill(Path(roundedRect: lower, cornerRadius: 5), with: .color(pipeColor))
            context.fill(Path(roundedRect: CGRect(x: pipe.x - 2, y: top - 7, width: Self.pipeWidth + 4, height: 7), cornerRadius: 2),
                         with: .color(lipColor))
            context.fill(Path(roundedRect: CGRect(x: pipe.x - 2, y: bottom, width: Self.pipeWidth + 4, height: 7), cornerRadius: 2),
                         with: .color(lipColor))
        }

        // Idle bird bobs gently while waiting.
        var y = birdY < 0 ? size.height / 2 : birdY
        if phase == .ready {
            bob += 0.08
            y += CGFloat(sin(bob)) * 3
        }
        let r = Self.radius
        let tilt = phase == .running ? max(-0.5, min(1.0, Double(velocity / (size.height * 6)))) : 0

        var bird = context
        bird.translateBy(x: Self.birdX, y: y)
        bird.rotate(by: .radians(tilt))
        bird.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)),
                  with: .color(Color(red: 1, green: 0.84, blue: 0.2)))
        bird.fill(Path(ellipseIn: CGRect(x: -r * 0.95, y: -r * 0.05, width: r * 1.1, height: r * 0.7)),
                  with: .color(Color(red: 1, green: 0.95, blue: 0.6)))
        bird.fill(Path(ellipseIn: CGRect(x: r * 0.1, y: -r * 0.8, width: r * 0.8, height: r * 0.8)), with: .color(.white))
        bird.fill(Path(ellipseIn: CGRect(x: r * 0.42, y: -r * 0.6, width: r * 0.34, height: r * 0.34)), with: .color(.black))
        var beak = Path()
        beak.move(to: CGPoint(x: r * 0.7, y: -r * 0.05))
        beak.addLine(to: CGPoint(x: r * 1.55, y: r * 0.2))
        beak.addLine(to: CGPoint(x: r * 0.7, y: r * 0.5))
        beak.closeSubpath()
        bird.fill(beak, with: .color(.orange))

        GameArt.scoreboard("\(score)   HI \(best)", in: &context, size: size)
        GameArt.message(message, in: &context, size: size)
    }

    private var message: String? {
        switch phase {
        case .ready: "Space or click to flap"
        case .paused: "Paused · click to keep going"
        case .over: newBest ? "New best: \(score)! Click to fly again" : "Bonk! \(score) · click to retry"
        case .running: nil
        }
    }
}
