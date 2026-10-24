// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Observation

/// A short event that pops out of the notch, like the iPhone's charging or AirPods alerts.
enum IslandAlert: Hashable {
    case welcome
    case charging(level: Int)
    case lowBattery(level: Int)
    case device(name: String, symbol: String)
    case nowPlaying(title: String)
    case timerDone
    /// A calendar event is about to start. `link` is its meeting URL, if any.
    case event(title: String, minutes: Int, link: String?)
    /// An app's unread badge went up.
    case message(app: String, count: String, path: String)
    /// A new NotchPal version is on GitHub.
    case updateAvailable(version: String)
    /// Downloading and installing an update.
    case updating
    /// NotchPal just restarted on a new version.
    case updated(version: String)
    /// An update didn't install.
    case updateFailed

    enum Category {
        case app
        case update
        case power
        case device
        case media
        case timer
        case calendar
        case message
    }

    var category: Category {
        switch self {
        case .welcome: .app
        case .charging, .lowBattery: .power
        case .device: .device
        case .nowPlaying: .media
        case .timerDone: .timer
        case .event: .calendar
        case .message: .message
        case .updateAvailable, .updating, .updated, .updateFailed: .update
        }
    }

    /// How long it stays. Nil means it waits for you (timer done).
    var duration: TimeInterval? {
        switch self {
        case .welcome: 3.4
        case .charging: 3
        case .lowBattery: 4.5
        case .device: 3.2
        case .nowPlaying: 3.2
        case .timerDone: nil
        case .event: 10
        case .message: 4
        case .updateAvailable: 15
        case .updating: nil
        case .updated: 4
        case .updateFailed: 6
        }
    }

    var width: CGFloat {
        switch self {
        case .welcome: 360
        case .charging, .lowBattery: 380
        case .device: 400
        case .nowPlaying: 440
        case .timerDone: 380
        case .event: 460
        case .message: 400
        case .updateAvailable: 440
        case .updating: 380
        case .updated: 380
        case .updateFailed: 420
        }
    }
}

/// Shows one alert at a time and queues the rest.
@MainActor
@Observable
final class AlertCenter {
    private(set) var current: IslandAlert?

    @ObservationIgnored private var waiting: [IslandAlert] = []
    @ObservationIgnored private var dismissWork: DispatchWorkItem?

    func show(_ alert: IslandAlert) {
        // Same kind replaces (a newer battery level wins), and "timer done" always jumps in.
        if current == nil || current?.category == alert.category || alert == .timerDone {
            present(alert)
            return
        }
        waiting.removeAll { $0.category == alert.category }
        waiting.append(alert)
    }

    /// Clears the current alert (or only one category) and shows the next in line.
    func dismiss(_ category: IslandAlert.Category? = nil) {
        if let category, current?.category != category {
            waiting.removeAll { $0.category == category }
            return
        }
        dismissWork?.cancel()
        current = nil
        guard !waiting.isEmpty else { return }
        let next = waiting.removeFirst()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.current == nil {
                    self.present(next)
                } else {
                    self.waiting.insert(next, at: 0)
                }
            }
        }
    }

    /// Opening the island answers whatever a short alert was saying, so those go away.
    func dismissTransient() {
        waiting.removeAll { $0.duration != nil }
        if let alert = current, alert.duration != nil {
            dismissWork?.cancel()
            current = nil
        }
    }

    private func present(_ alert: IslandAlert) {
        dismissWork?.cancel()
        current = alert
        guard let duration = alert.duration else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
