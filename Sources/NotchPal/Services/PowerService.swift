// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import IOKit.ps
import Observation

/// Battery level, charging and time left, from IOKit. No permissions needed.
@MainActor
@Observable
final class PowerService {
    private(set) var level = 100
    private(set) var isCharging = false
    private(set) var onPower = false
    private(set) var hasBattery = false
    /// Minutes until empty (on battery) or full (charging). Nil while macOS is still estimating.
    private(set) var minutesLeft: Int?
    /// Low Power Mode is on (System Settings → Battery). The battery turns yellow, like on iPhone.
    private(set) var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    @ObservationIgnored var onAlert: (@MainActor (IslandAlert) -> Void)?

    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var powerModeObserver: NSObjectProtocol?
    @ObservationIgnored private var warned: Set<Int> = []
    @ObservationIgnored private var primed = false

    func start() {
        guard runLoopSource == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        let created = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<PowerService>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { service.refresh() }
        }, context)
        if let source = created?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, CFRunLoopMode.defaultMode)
        }
        powerModeObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let on = ProcessInfo.processInfo.isLowPowerModeEnabled
                if self.lowPowerMode != on { self.lowPowerMode = on }
            }
        }
        refresh()
    }

    /// "2:15 left", "40 min to full", "Fully charged"…
    var timeDescription: String {
        if onPower && !isCharging && level >= 99 { return "Fully charged" }
        guard let minutes = minutesLeft, minutes > 0 else {
            return isCharging ? "Charging" : (onPower ? "Plugged in" : "On battery")
        }
        let text = minutes >= 60 ? String(format: "%d:%02d", minutes / 60, minutes % 60) : "\(minutes) min"
        return isCharging ? "\(text) to full" : "\(text) left"
    }

    private func refresh() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue()
        else { return }

        for item in list as NSArray {
            let powerSource = item as CFTypeRef
            guard let unmanaged = IOPSGetPowerSourceDescription(blob, powerSource) else { continue }
            let description = unmanaged.takeUnretainedValue() as NSDictionary
            guard (description["Type"] as? String) == "InternalBattery" else { continue }

            let current = description["Current Capacity"] as? Int ?? 0
            let capacity = description["Max Capacity"] as? Int ?? 100
            let percent = capacity > 0 ? Int((Double(current) / Double(capacity) * 100).rounded()) : current
            let charging = description["Is Charging"] as? Bool ?? false
            let plugged = (description["Power Source State"] as? String) == "AC Power"
            let key = charging ? "Time to Full Charge" : "Time to Empty"
            let minutes = description[key] as? Int
            apply(level: percent, charging: charging, plugged: plugged,
                  minutes: (minutes ?? -1) > 0 ? minutes : nil)
            return
        }
    }

    private func apply(level newLevel: Int, charging: Bool, plugged: Bool, minutes: Int?) {
        let wasPlugged = onPower
        if !hasBattery { hasBattery = true }
        if level != newLevel { level = newLevel }
        if isCharging != charging { isCharging = charging }
        if onPower != plugged { onPower = plugged }
        if minutesLeft != minutes { minutesLeft = minutes }

        // The first reading is just the starting point, not an event.
        guard primed else {
            primed = true
            return
        }
        if plugged && !wasPlugged {
            warned.removeAll()
            onAlert?(.charging(level: newLevel))
        }
        if !plugged {
            for threshold in [20, 10] where newLevel <= threshold && !warned.contains(threshold) {
                warned.insert(threshold)
                onAlert?(.lowBattery(level: newLevel))
                break
            }
        }
    }
}
