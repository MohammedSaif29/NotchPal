// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import Observation

/// Pong against the notch. Your paddle is on the left and follows the mouse. First to 5 wins.
@MainActor
@Observable
final class PongGame: NotchGame {
    private(set) var phase: GamePhase = .ready
    /// Total games won against the computer.
    private(set) var best: Int

    private let settings: SettingsStore
    @ObservationIgnored private var tuning: Tuning
    @ObservationIgnored private var playerY: CGFloat = 0
    @ObservationIgnored private var targetY: CGFloat?
    @ObservationIgnored private var computerY: CGFloat = 0
    @ObservationIgnored private var ball = CGPoint.zero
    @ObservationIgnored private var ballVelocity = CGVector.zero
    @ObservationIgnored private var playerPoints = 0
    @ObservationIgnored private var computerPoints = 0
    @ObservationIgnored private var serveDelay: Double = 0
    @ObservationIgnored private var lastFrame: Date?
    @ObservationIgnored private var placed = false
    @ObservationIgnored private var finishing = false
    @ObservationIgnored private var playerWon = false
    @ObservationIgnored private var lastSize = CGSize(width: 400, height: 120)

    private static let bestKey = "pong.wins"
    private static let paddleWidth: CGFloat = 6
    private static let inset: CGFloat = 14
    private static let radius: CGFloat = 5
    private static let winningScore = 5

    private struct Tuning {
        var paddleRatio: CGFloat
        var ballSpeed: CGFloat
        var maxSpeed: CGFloat
        var computerSpeed: CGFloat

        static func make(_ difficulty: Difficulty) -> Tuning {
            switch difficulty {
            case .easy: Tuning(paddleRatio: 0.4, ballSpeed: 210, maxSpeed: 420, computerSpeed: 140)
            case .normal: Tuning(paddleRatio: 0.32, ballSpeed: 260, maxSpeed: 540, computerSpeed: 215)
            case .hard: Tuning(paddleRatio: 0.26, ballSpeed: 320, maxSpeed: 680, computerSpeed: 310)
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
        switch input {
        case .action:
            start()
        case .up:
            if phase != .running { start() }
            targetY = (targetY ?? playerY) - 28
        case .down:
            if phase != .running { start() }
            targetY = (targetY ?? playerY) + 28
        case .left, .right:
            break
        }
    }

    func tap(at point: CGPoint, in size: CGSize) {
        start()
    }

    func pointer(at point: CGPoint?, in size: CGSize) {
        if let point {
            targetY = point.y
        }
    }

    private func start() {
        switch phase {
        case .ready, .over:
            tuning = Tuning.make(settings.difficulty)
            playerPoints = 0
            computerPoints = 0
            finishing = false
            playerWon = false
            serve(towardComputer: Bool.random())
            phase = .running
        case .paused:
            lastFrame = nil
            phase = .running
        case .running:
            break
        }
    }

    private func serve(towardComputer: Bool) {
        ball = CGPoint(x: lastSize.width / 2, y: lastSize.height / 2)
        let angle = Double.random(in: -0.45...0.45)
        let direction: CGFloat = towardComputer ? 1 : -1
        ballVelocity = CGVector(dx: CGFloat(cos(angle)) * tuning.ballSpeed * direction,
                                dy: CGFloat(sin(angle)) * tuning.ballSpeed)
        serveDelay = 0.6
        lastFrame = nil
    }

    func pause() {
        if phase == .running { phase = .paused }
    }

    func reset() {
        placed = false
        playerPoints = 0
        computerPoints = 0
        finishing = false
        if phase != .ready { phase = .ready }
    }

    func clearBest() {
        best = 0
        GameArt.saveBest(0, Self.bestKey)
    }

    // MARK: Simulation

    func step(to now: Date, size: CGSize) {
        lastSize = size
        let paddle = size.height * tuning.paddleRatio
        let half = paddle / 2
        if !placed {
            playerY = size.height / 2
            computerY = size.height / 2
            ball = CGPoint(x: size.width / 2, y: size.height / 2)
            placed = true
        }
        guard phase == .running, !finishing else {
            lastFrame = now
            return
        }
        let dt = CGFloat(min(now.timeIntervalSince(lastFrame ?? now), 1.0 / 30.0))
        lastFrame = now

        // Your paddle glides toward the mouse.
        if let target = targetY {
            let goal = min(size.height - half, max(half, target))
            playerY += (goal - playerY) * min(1, dt * 18)
        }

        // The computer chases the ball when it's coming, and drifts home when it isn't.
        let aim = ballVelocity.dx > 0 ? ball.y : size.height / 2
        let move = tuning.computerSpeed * dt
        computerY += min(move, max(-move, aim - computerY))
        computerY = min(size.height - half, max(half, computerY))

        if serveDelay > 0 {
            serveDelay -= Double(dt)
            return
        }

        ball.x += ballVelocity.dx * dt
        ball.y += ballVelocity.dy * dt

        let r = Self.radius
        if ball.y < r {
            ball.y = r
            ballVelocity.dy = abs(ballVelocity.dy)
        } else if ball.y > size.height - r {
            ball.y = size.height - r
            ballVelocity.dy = -abs(ballVelocity.dy)
        }

        let leftFace = Self.inset + Self.paddleWidth
        if ballVelocity.dx < 0, ball.x - r <= leftFace, ball.x - r >= Self.inset - 6,
           abs(ball.y - playerY) <= half + r {
            bounce(offset: (ball.y - playerY) / half, direction: 1)
            ball.x = leftFace + r
        }

        let rightFace = size.width - Self.inset - Self.paddleWidth
        if ballVelocity.dx > 0, ball.x + r >= rightFace, ball.x + r <= size.width - Self.inset + 6,
           abs(ball.y - computerY) <= half + r {
            bounce(offset: (ball.y - computerY) / half, direction: -1)
            ball.x = rightFace - r
        }

        if ball.x < -r {
            computerPoints += 1
            pointScored()
        } else if ball.x > size.width + r {
            playerPoints += 1
            pointScored()
        }
    }

    /// Where the ball hits the paddle sets the angle, and every hit speeds it up a little.
    private func bounce(offset: CGFloat, direction: CGFloat) {
        let speed = min(tuning.maxSpeed, hypot(ballVelocity.dx, ballVelocity.dy) * 1.06)
        let angle = Double(max(-1, min(1, offset))) * 0.9
        ballVelocity = CGVector(dx: CGFloat(cos(angle)) * speed * direction, dy: CGFloat(sin(angle)) * speed)
        GameArt.sound("Tink", volume: 0.16, enabled: settings.gameSounds)
    }

    private func pointScored() {
        if playerPoints >= Self.winningScore || computerPoints >= Self.winningScore {
            finishing = true
            let won = playerPoints > computerPoints
            GameArt.sound(won ? "Hero" : "Basso", volume: 0.25, enabled: settings.gameSounds)
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.playerWon = won
                    if won {
                        self.best += 1
                        GameArt.saveBest(self.best, Self.bestKey)
                    }
                    self.phase = .over
                }
            }
            return
        }
        // Serve toward whoever just lost the point.
        serve(towardComputer: ball.x > lastSize.width / 2)
    }

    // MARK: Drawing

    func draw(in context: inout GraphicsContext, size: CGSize) {
        let paddle = size.height * tuning.paddleRatio

        var net = Path()
        var y: CGFloat = 4
        while y < size.height {
            net.addRect(CGRect(x: size.width / 2 - 1, y: y, width: 2, height: 6))
            y += 12
        }
        context.fill(net, with: .color(.white.opacity(0.15)))

        let scores = Text("\(playerPoints)      \(computerPoints)")
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .foregroundColor(.white.opacity(0.18))
        context.draw(scores, at: CGPoint(x: size.width / 2, y: 22))

        let you = CGRect(x: Self.inset, y: playerY - paddle / 2, width: Self.paddleWidth, height: paddle)
        let them = CGRect(x: size.width - Self.inset - Self.paddleWidth, y: computerY - paddle / 2,
                          width: Self.paddleWidth, height: paddle)
        context.fill(Path(roundedRect: you, cornerRadius: 3), with: .color(.white))
        context.fill(Path(roundedRect: them, cornerRadius: 3), with: .color(Color(red: 1, green: 0.58, blue: 0.2)))

        if phase == .running || phase == .paused {
            let r = Self.radius
            context.fill(Path(ellipseIn: CGRect(x: ball.x - r, y: ball.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(.white))
        }

        GameArt.scoreboard("WINS \(best)", in: &context, size: size)
        GameArt.message(message, in: &context, size: size)
    }

    private var message: String? {
        switch phase {
        case .ready: "Click to serve · first to \(Self.winningScore) wins"
        case .paused: "Paused · click to keep going"
        case .over: playerWon ? "You win \(playerPoints)–\(computerPoints)! Click for a rematch" : "The notch wins \(computerPoints)–\(playerPoints) · click to try again"
        case .running: nil
        }
    }
}
