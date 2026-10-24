// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI
import Observation

enum GamePhase: Equatable {
    case ready
    case running
    case paused
    case over
}

enum GameInput {
    case up
    case down
    case left
    case right
    case action
}

enum GameKind: String, CaseIterable, Identifiable {
    case runner
    case flappy
    case snake
    case pong

    var id: Self { self }

    var title: String {
        switch self {
        case .runner: "Runner"
        case .flappy: "Flappy"
        case .snake: "Snake"
        case .pong: "Pong"
        }
    }

    var symbol: String {
        switch self {
        case .runner: "figure.run"
        case .flappy: "bird.fill"
        case .snake: "scribble.variable"
        case .pong: "tennisball.fill"
        }
    }

    var hint: String {
        switch self {
        case .runner: "Space or click to jump"
        case .flappy: "Space or click to flap"
        case .snake: "Arrow keys or WASD to steer"
        case .pong: "Move the mouse (or ↑ ↓) to play"
        }
    }
}

/// A tiny game that lives inside the island. The island draws it every frame with a Canvas.
@MainActor
protocol NotchGame: AnyObject {
    var phase: GamePhase { get }
    var best: Int { get }
    func handle(_ input: GameInput)
    func tap(at point: CGPoint, in size: CGSize)
    func pointer(at point: CGPoint?, in size: CGSize)
    func pause()
    func reset()
    func clearBest()
    /// Moves the world forward. Runs inside drawing, so it must only change unobserved state.
    func step(to now: Date, size: CGSize)
    func draw(in context: inout GraphicsContext, size: CGSize)
}

extension NotchGame {
    func tap(at point: CGPoint, in size: CGSize) {
        handle(.action)
    }

    func pointer(at point: CGPoint?, in size: CGSize) {}
}

/// Owns the games and remembers which one you played last.
@MainActor
@Observable
final class GameHub {
    var selected: GameKind {
        didSet {
            guard oldValue != selected else { return }
            game(for: oldValue).pause()
            settings.lastGame = selected.rawValue
        }
    }

    let runner: RunnerGame
    let flappy: FlappyGame
    let snake: SnakeGame
    let pong: PongGame
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
        runner = RunnerGame(settings: settings)
        flappy = FlappyGame(settings: settings)
        snake = SnakeGame(settings: settings)
        pong = PongGame(settings: settings)
        selected = GameKind(rawValue: settings.lastGame) ?? .runner
    }

    var current: any NotchGame { game(for: selected) }

    func game(for kind: GameKind) -> any NotchGame {
        switch kind {
        case .runner: return runner
        case .flappy: return flappy
        case .snake: return snake
        case .pong: return pong
        }
    }

    func pauseAll() {
        for kind in GameKind.allCases {
            game(for: kind).pause()
        }
    }

    func resetAll() {
        for kind in GameKind.allCases {
            game(for: kind).reset()
        }
    }

    func clearScores() {
        for kind in GameKind.allCases {
            game(for: kind).clearBest()
        }
    }
}

/// Drawing and sound helpers shared by the games.
@MainActor
enum GameArt {
    static func scoreboard(_ text: String, in context: inout GraphicsContext, size: CGSize) {
        let label = Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(.white.opacity(0.7))
        context.draw(label, at: CGPoint(x: size.width - 10, y: 12), anchor: .trailing)
    }

    /// A message in a dark pill across the middle, e.g. "Press Space to start".
    static func message(_ text: String?, in context: inout GraphicsContext, size: CGSize) {
        guard let text else { return }
        let label = Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(.white.opacity(0.94))
        let resolved = context.resolve(label)
        let measured = resolved.measure(in: size)
        let pill = CGRect(x: (size.width - measured.width) / 2 - 14,
                          y: size.height / 2 - measured.height / 2 - 7,
                          width: measured.width + 28,
                          height: measured.height + 14)
        context.fill(Path(roundedRect: pill, cornerRadius: pill.height / 2), with: .color(.black.opacity(0.6)))
        context.draw(resolved, at: CGPoint(x: pill.midX, y: pill.midY), anchor: .center)
    }

    static func sound(_ name: String, volume: Float = 0.3, enabled: Bool) {
        guard enabled, let sound = NSSound(named: name)?.copy() as? NSSound else { return }
        sound.volume = volume
        sound.play()
    }

    static func loadBest(_ key: String) -> Int {
        UserDefaults.standard.integer(forKey: key)
    }

    static func saveBest(_ value: Int, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
