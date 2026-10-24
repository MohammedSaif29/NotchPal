// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Observation

/// A single countdown timer that lives in the notch.
@MainActor
@Observable
final class TimerService {
    private(set) var endDate: Date?
    private(set) var pausedRemaining: TimeInterval?
    private(set) var total: TimeInterval = 0
    private(set) var finished = false

    @ObservationIgnored var onFinish: (@MainActor () -> Void)?
    @ObservationIgnored private var ticker: Timer?

    var isActive: Bool { endDate != nil || pausedRemaining != nil }
    var isPaused: Bool { pausedRemaining != nil }

    func remaining(at now: Date = .now) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endDate else { return 0 }
        return max(0, endDate.timeIntervalSince(now))
    }

    func progress(at now: Date = .now) -> Double {
        if finished { return 1 }
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - remaining(at: now) / total))
    }

    func start(minutes: Double) {
        total = minutes * 60
        endDate = Date().addingTimeInterval(total)
        pausedRemaining = nil
        finished = false
        startTicking()
    }

    /// Adds time to the running timer.
    func add(minutes: Double) {
        let extra = minutes * 60
        if let paused = pausedRemaining {
            pausedRemaining = paused + extra
        } else if let end = endDate {
            endDate = end.addingTimeInterval(extra)
        } else {
            return
        }
        total += extra
    }

    func togglePause() {
        if let paused = pausedRemaining {
            endDate = Date().addingTimeInterval(paused)
            pausedRemaining = nil
            startTicking()
        } else if endDate != nil {
            pausedRemaining = remaining()
            endDate = nil
            ticker?.invalidate()
        }
    }

    func cancel() {
        endDate = nil
        pausedRemaining = nil
        finished = false
        ticker?.invalidate()
    }

    func dismissFinished() {
        finished = false
    }

    private func startTicking() {
        ticker?.invalidate()
        let tick = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkFinished() }
        }
        RunLoop.main.add(tick, forMode: .common)
        ticker = tick
    }

    private func checkFinished() {
        guard let endDate, Date() >= endDate else { return }
        self.endDate = nil
        ticker?.invalidate()
        finished = true
        NSSound(named: "Glass")?.play()
        onFinish?()
    }
}

/// "4:05" or "1:02:30". Countdowns round up so "0:00" only shows when time is really up.
func formatClock(_ seconds: TimeInterval, roundUp: Bool = true) -> String {
    let value = max(0, seconds)
    let total = Int(roundUp ? value.rounded(.up) : value.rounded(.down))
    if total >= 3600 {
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
    return String(format: "%d:%02d", total / 60, total % 60)
}
