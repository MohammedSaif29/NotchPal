// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import Observation

/// Snake: eat the dots, don't bite yourself. Easy wraps around the edges.
@MainActor
@Observable
final class SnakeGame: NotchGame {
    private(set) var phase: GamePhase = .ready
    private(set) var best: Int

    private struct Cell: Equatable {
        var x: Int
        var y: Int
    }

    private let settings: SettingsStore
    @ObservationIgnored private var segments: [Cell] = []
    @ObservationIgnored private var direction = Cell(x: 1, y: 0)
    @ObservationIgnored private var queuedTurns: [Cell] = []
    @ObservationIgnored private var food = Cell(x: 0, y: 0)
    @ObservationIgnored private var columns = 0
    @ObservationIgnored private var rows = 0
    @ObservationIgnored private var interval: Double = 0.1
    @ObservationIgnored private var accumulator: Double = 0
    @ObservationIgnored private var score = 0
    @ObservationIgnored private var lastFrame: Date?
    @ObservationIgnored private var crashed = false
    @ObservationIgnored private var needsSetup = true
    @ObservationIgnored private var newBest = false

    private static let bestKey = "snake.best"
    private static let cellSize: CGFloat = 10

    init(settings: SettingsStore) {
        self.settings = settings
        best = GameArt.loadBest(Self.bestKey)
    }

    private var startInterval: Double {
        switch settings.difficulty {
        case .easy: 0.14
        case .normal: 0.1
        case .hard: 0.075
        }
    }

    // MARK: Input

    func handle(_ input: GameInput) {
        let turn: Cell?
        switch input {
        case .up: turn = Cell(x: 0, y: -1)
        case .down: turn = Cell(x: 0, y: 1)
        case .left: turn = Cell(x: -1, y: 0)
        case .right: turn = Cell(x: 1, y: 0)
        case .action: turn = nil
        }
        if phase != .running {
            start()
        }
        if let turn {
            queue(turn)
        }
    }

    private func start() {
        switch phase {
        case .paused:
            lastFrame = nil
            phase = .running
        case .ready, .over:
            needsSetup = true
            phase = .running
        case .running:
            break
        }
    }

    /// Remembers up to three quick turns, and ignores turning straight back into yourself.
    private func queue(_ turn: Cell) {
        let last = queuedTurns.last ?? direction
        guard turn != last, !(turn.x == -last.x && turn.y == -last.y), queuedTurns.count < 3 else { return }
        queuedTurns.append(turn)
    }

    func pause() {
        if phase == .running { phase = .paused }
    }

    func reset() {
        needsSetup = true
        if phase != .ready { phase = .ready }
    }

    func clearBest() {
        best = 0
        GameArt.saveBest(0, Self.bestKey)
    }

    // MARK: Simulation

    func step(to now: Date, size: CGSize) {
        let newColumns = max(8, Int(size.width / Self.cellSize))
        let newRows = max(5, Int(size.height / Self.cellSize))
        if needsSetup || newColumns != columns || newRows != rows {
            setUp(columns: newColumns, rows: newRows)
        }
        guard phase == .running, !crashed else {
            lastFrame = now
            return
        }
        let dt = min(now.timeIntervalSince(lastFrame ?? now), 0.1)
        lastFrame = now
        accumulator += dt
        while accumulator >= interval && !crashed {
            accumulator -= interval
            advance()
        }
    }

    private func setUp(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
        let start = Cell(x: columns / 3, y: rows / 2)
        segments = [start, Cell(x: start.x - 1, y: start.y), Cell(x: start.x - 2, y: start.y)]
        direction = Cell(x: 1, y: 0)
        queuedTurns = []
        interval = startInterval
        accumulator = 0
        score = 0
        crashed = false
        newBest = false
        needsSetup = false
        lastFrame = nil
        placeFood()
    }

    private func advance() {
        if !queuedTurns.isEmpty {
            direction = queuedTurns.removeFirst()
        }
        guard let first = segments.first else { return }
        var head = Cell(x: first.x + direction.x, y: first.y + direction.y)

        if settings.difficulty == .easy {
            head.x = (head.x + columns) % columns
            head.y = (head.y + rows) % rows
        } else if head.x < 0 || head.y < 0 || head.x >= columns || head.y >= rows {
            crash()
            return
        }

        let grows = head == food
        let body = grows ? segments : Array(segments.dropLast())
        if body.contains(head) {
            crash()
            return
        }
        segments = [head] + body

        if grows {
            score += 1
            GameArt.sound("Pop", volume: 0.18, enabled: settings.gameSounds)
            placeFood()
            if settings.difficulty == .hard {
                interval = max(0.045, interval * 0.97)
            }
        }
    }

    private func placeFood() {
        guard columns > 0, rows > 0 else { return }
        for _ in 0..<300 {
            let cell = Cell(x: Int.random(in: 0..<columns), y: Int.random(in: 0..<rows))
            if !segments.contains(cell) {
                food = cell
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
        let cell = Self.cellSize
        let originX = (size.width - CGFloat(columns) * cell) / 2
        let originY = (size.height - CGFloat(rows) * cell) / 2
        let board = CGRect(x: originX, y: originY, width: CGFloat(columns) * cell, height: CGFloat(rows) * cell)

        if settings.difficulty != .easy {
            context.stroke(Path(roundedRect: board.insetBy(dx: -1, dy: -1), cornerRadius: 6),
                           with: .color(.white.opacity(0.14)), lineWidth: 1)
        }

        func rect(_ c: Cell, inset: CGFloat) -> CGRect {
            CGRect(x: originX + CGFloat(c.x) * cell, y: originY + CGFloat(c.y) * cell, width: cell, height: cell)
                .insetBy(dx: inset, dy: inset)
        }

        // Food with a soft glow.
        let foodRect = rect(food, inset: 1.5)
        context.fill(Path(ellipseIn: foodRect.insetBy(dx: -3, dy: -3)), with: .color(.red.opacity(0.25)))
        context.fill(Path(ellipseIn: foodRect), with: .color(Color(red: 1, green: 0.3, blue: 0.35)))

        // Body fades from bright head to darker tail.
        let count = max(1, segments.count)
        for (index, segment) in segments.enumerated().reversed() {
            let fade = 1 - Double(index) / Double(count) * 0.55
            context.fill(Path(roundedRect: rect(segment, inset: 1), cornerRadius: 3),
                         with: .color(Color(red: 0.3 * fade, green: 0.9 * fade, blue: 0.5 * fade)))
        }

        if let head = segments.first {
            let r = rect(head, inset: 1)
            let eye: CGFloat = 2
            let offsetX = CGFloat(direction.x) * 1.5
            let offsetY = CGFloat(direction.y) * 1.5
            let horizontal = direction.y == 0
            let first = horizontal ? CGPoint(x: r.midX + offsetX, y: r.midY - 2.2) : CGPoint(x: r.midX - 2.2, y: r.midY + offsetY)
            let second = horizontal ? CGPoint(x: r.midX + offsetX, y: r.midY + 2.2) : CGPoint(x: r.midX + 2.2, y: r.midY + offsetY)
            for point in [first, second] {
                context.fill(Path(ellipseIn: CGRect(x: point.x - eye / 2, y: point.y - eye / 2, width: eye, height: eye)),
                             with: .color(.black))
            }
        }

        GameArt.scoreboard("\(score)   HI \(best)", in: &context, size: size)
        GameArt.message(message, in: &context, size: size)
    }

    private var message: String? {
        switch phase {
        case .ready: "Arrow keys to start · eat the red dots"
        case .paused: "Paused · press an arrow key"
        case .over: newBest ? "New best: \(score)! Space to go again" : "Game over · \(score) · Space to retry"
        case .running: nil
        }
    }
}
