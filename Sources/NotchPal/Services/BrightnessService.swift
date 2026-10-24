// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import CoreGraphics
import Observation

/// The built-in screen's brightness, for the slider under the volume.
///
/// macOS has no public way for apps to change the brightness on Apple-silicon Macs, so this uses
/// DisplayServices, the system framework that popular brightness apps use too. It needs no
/// permission. If a future macOS removes it, `isAvailable` turns false and the slider hides itself.
@MainActor
@Observable
final class BrightnessService {
    /// 0 is darkest, 1 is brightest.
    private(set) var level: Double = 0.5
    private(set) var isAvailable = false

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    @ObservationIgnored private var getBrightness: GetBrightness?
    @ObservationIgnored private var setBrightness: SetBrightness?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var watchers = 0

    init() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        if let handle = dlopen(path, RTLD_LAZY),
           let get = dlsym(handle, "DisplayServicesGetBrightness"),
           let set = dlsym(handle, "DisplayServicesSetBrightness") {
            getBrightness = unsafeBitCast(get, to: GetBrightness.self)
            setBrightness = unsafeBitCast(set, to: SetBrightness.self)
        }
        refresh()
    }

    /// While the slider is on screen, keep it in step with the brightness keys.
    func startWatching() {
        watchers += 1
        refresh()
        guard timer == nil else { return }
        let tick = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
    }

    func stopWatching() {
        watchers = max(0, watchers - 1)
        if watchers == 0 {
            timer?.invalidate()
            timer = nil
        }
    }

    func set(_ value: Double) {
        guard let setBrightness, let display = Self.builtInDisplay() else { return }
        let clamped = min(1, max(0, value))
        if level != clamped { level = clamped }
        _ = setBrightness(display, Float(clamped))
    }

    func refresh() {
        guard let getBrightness, let display = Self.builtInDisplay() else {
            if isAvailable { isAvailable = false }
            return
        }
        var value: Float = 0
        let ok = getBrightness(display, &value) == 0
        if isAvailable != ok { isAvailable = ok }
        if ok && abs(Double(value) - level) > 0.005 {
            level = Double(value)
        }
    }

    /// The MacBook's own screen (external monitors can't be changed this way).
    private static func builtInDisplay() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.first { CGDisplayIsBuiltin($0) != 0 }
    }
}
