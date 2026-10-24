// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import ApplicationServices
import Observation

/// An app with an unread badge on its Dock icon, like Messages showing "3".
struct AppBadge: Identifiable, Equatable {
    let name: String
    /// "3", "99+", or "•".
    let count: String
    /// Path of the app bundle, used for its icon and to open it.
    let path: String

    var id: String { path }
}

/// Notifications in the notch.
///
/// macOS doesn't let apps read other apps' notifications. What it does allow, with the
/// Accessibility permission, is reading the unread badges on Dock icons (the same thing
/// apps like Badgeify do). NotchPal checks them every couple of seconds, shows them in the
/// Notifications tab, and pops an alert when a count goes up.
@MainActor
@Observable
final class BadgeMonitor {
    private(set) var badges: [AppBadge] = []
    private(set) var trusted = AXIsProcessTrusted()
    private(set) var enabled = false
    /// False when the permission is on but the Dock couldn't be read.
    private(set) var dockReadable = true
    /// True while Fix It is resetting the permission.
    private(set) var fixing = false

    @ObservationIgnored var onNewBadge: (@MainActor (AppBadge) -> Void)?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var previous: [String: String] = [:]
    @ObservationIgnored private var primed = false
    @ObservationIgnored private var reading = false
    /// Talking to the Dock can be slow if it's busy, so it never happens on the main thread.
    private let queue = DispatchQueue(label: "notchpal.badges", qos: .utility)

    func setEnabled(_ on: Bool) {
        enabled = on
        timer?.invalidate()
        timer = nil
        primed = false
        guard on else {
            if !badges.isEmpty { badges = [] }
            return
        }
        let tick = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
        poll()
    }

    /// Shows macOS's "allow Accessibility" prompt.
    func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)
    }

    /// macOS remembers the Accessibility permission for one exact copy of an app. After NotchPal
    /// is updated, System Settings can still show it switched on while macOS refuses the new copy.
    /// This clears NotchPal's old entry and asks again, so you can switch it on for real.
    func fixPermission() {
        guard !fixing else { return }
        fixing = true
        let bundleID = Bundle.main.bundleIdentifier ?? "com.saif.notchpal"
        queue.async { [weak self] in
            let reset = Process()
            reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            reset.arguments = ["reset", "Accessibility", bundleID]
            reset.standardOutput = FileHandle.nullDevice
            reset.standardError = FileHandle.nullDevice
            if (try? reset.run()) != nil {
                reset.waitUntilExit()
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.fixing = false
                    self.requestAccess()
                    self.openAccessibilitySettings()
                    self.poll()
                }
            }
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func open(_ badge: AppBadge) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: badge.path),
                                           configuration: NSWorkspace.OpenConfiguration())
    }

    private func poll() {
        let isTrusted = AXIsProcessTrusted()
        if isTrusted != trusted { trusted = isTrusted }
        guard isTrusted else {
            if !badges.isEmpty { badges = [] }
            return
        }
        guard !reading else { return } // The last read is still running.
        reading = true
        queue.async { [weak self] in
            let reading = DockReader.read()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.finish(reading.badges, dockItems: reading.items) }
            }
        }
    }

    private func finish(_ current: [AppBadge], dockItems: Int) {
        reading = false
        guard enabled else { return }
        let readable = dockItems > 0
        if readable != dockReadable { dockReadable = readable }
        if current != badges { badges = current }

        var counts: [String: String] = [:]
        for badge in current {
            counts[badge.path] = badge.count
        }
        if primed {
            for badge in current where Self.isNew(badge.count, comparedTo: previous[badge.path]) {
                onNewBadge?(badge)
            }
        }
        previous = counts
        primed = true
    }

    private static func isNew(_ count: String, comparedTo old: String?) -> Bool {
        guard let old else { return true }
        if let before = Int(old), let after = Int(count) {
            return after > before
        }
        return old != count
    }
}

/// Reads badges from the Dock through the Accessibility API.
private enum DockReader {
    /// The badges, and how many Dock icons were seen (0 means the Dock couldn't be read).
    static func read() -> (badges: [AppBadge], items: Int) {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return ([], 0)
        }
        let root = AXUIElementCreateApplication(dock.processIdentifier)
        var found: [AppBadge] = []
        var items = 0
        // The Dock's icons sit a level or two down. Walking a few levels keeps this working
        // if a macOS update rearranges them.
        var level = children(of: root)
        for _ in 0..<4 where !level.isEmpty {
            var next: [AXUIElement] = []
            for element in level {
                if attribute(element, "AXTitle") is String, attribute(element, "AXURL") != nil {
                    items += 1
                }
                if let label = attribute(element, "AXStatusLabel") as? String, !label.isEmpty {
                    let name = attribute(element, "AXTitle") as? String ?? "App"
                    let url = attribute(element, "AXURL") as? URL
                    let path = url?.path ?? "/Applications/\(name).app"
                    if !found.contains(where: { $0.path == path }) {
                        found.append(AppBadge(name: name, count: label, path: path))
                    }
                }
                next.append(contentsOf: children(of: element))
            }
            level = next
        }
        return (found, items)
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        (attribute(element, "AXChildren") as? [AXUIElement]) ?? []
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
