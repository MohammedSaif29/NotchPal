// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import CoreAudio
import Observation

/// Something live on the Mac, shown in the notch like a Live Activity on Apple's island.
enum LiveKind: Equatable {
    case screenRecording
    case call
    case recording
    case music
    case timer
}

struct LiveItem: Equatable, Identifiable {
    var kind: LiveKind
    /// The app it belongs to, for calls and recordings.
    var bundleID: String?
    var appName: String = ""
    /// When it started, for the running clock.
    var since: Date?

    var id: String { "\(kind)-\(bundleID ?? "")" }

    var title: String {
        switch kind {
        case .screenRecording: return "Recording screen"
        case .call: return appName.isEmpty ? "On a call" : "\(appName) call"
        case .recording: return appName.isEmpty ? "Recording" : "Recording · \(appName)"
        case .music: return "Now playing"
        case .timer: return "Timer"
        }
    }

    /// The colour Apple uses for this kind of activity.
    var tint: NSColor {
        switch kind {
        case .screenRecording, .recording: return .systemRed
        case .call: return .systemGreen
        case .music: return .white
        case .timer: return .systemOrange
        }
    }
}

/// Watches for calls, recordings and screen recordings, and for Siri listening. It only looks at
/// which apps are using the microphone and which small windows are in the menu bar, so it needs no
/// permissions and never hears or sees anything.
@MainActor
@Observable
final class ActivityMonitor {
    /// Apps on a call: they're using the microphone and are a calling app or a browser (Meet and
    /// the like run in browsers).
    private(set) var call: LiveItem?
    /// Any other app using the microphone, like Voice Memos.
    private(set) var recording: LiveItem?
    /// macOS's own screen recording (⇧⌘5) is running.
    private(set) var screenRecording: LiveItem?
    /// Siri is listening or showing.
    private(set) var siriActive = false

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var checking = false
    @ObservationIgnored private var firstSeen: [String: Date] = [:]
    private let queue = DispatchQueue(label: "notchpal.activities", qos: .utility)

    static let callApps: Set<String> = [
        "com.apple.FaceTime", "us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams",
        "com.tinyspeck.slackmacgap", "com.hnc.Discord", "net.whatsapp.WhatsApp", "desktop.WhatsApp",
        "com.skype.skype", "com.cisco.webexmeetingsapp", "com.webex.meetingmanager", "ru.keepcoder.Telegram",
        "org.whispersystems.signal-desktop", "com.apple.MobileSMS",
    ]
    static let browsers: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "org.mozilla.firefox",
        "com.microsoft.edgemac", "com.brave.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
        "com.openai.atlas", "ai.perplexity.comet",
    ]

    func start() {
        guard timer == nil else { return }
        let tick = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        call = nil
        recording = nil
        screenRecording = nil
        siriActive = false
    }

    private func poll() {
        guard !checking else { return }
        checking = true
        let own = Bundle.main.bundleIdentifier ?? ""
        queue.async { [weak self] in
            let micUsers = ActivityProbe.microphoneUsers()
            let windows = ActivityProbe.menuBarSignals()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.update(micUsers: micUsers, windows: windows, own: own)
                }
            }
        }
    }

    private func update(micUsers: [ActivityProbe.MicUser], windows: ActivityProbe.WindowSignals, own: String) {
        checking = false
        let now = Date()
        var seen: Set<String> = []
        func since(_ key: String) -> Date {
            seen.insert(key)
            if let date = firstSeen[key] { return date }
            firstSeen[key] = now
            return now
        }

        var newCall: LiveItem?
        var newRecording: LiveItem?
        var siri = windows.siriShowing
        for user in micUsers {
            let id = user.bundleID.lowercased()
            if id.contains("siri") || id.contains("corespeech") || id.contains("assistant") {
                siri = true
                continue
            }
            guard user.bundleID != own, let app = Self.owningApp(for: user) else { continue }
            if Self.callApps.contains(app.bundleID) || Self.browsers.contains(app.bundleID) {
                if newCall == nil {
                    newCall = LiveItem(kind: .call, bundleID: app.bundleID, appName: app.name, since: since("call-\(app.bundleID)"))
                }
            } else if newRecording == nil {
                newRecording = LiveItem(kind: .recording, bundleID: app.bundleID, appName: app.name, since: since("rec-\(app.bundleID)"))
            }
        }
        let newScreen = windows.screenRecording
            ? LiveItem(kind: .screenRecording, bundleID: "com.apple.screencaptureui", appName: "Screenshot", since: since("screen"))
            : nil
        firstSeen = firstSeen.filter { seen.contains($0.key) }

        if newCall != call { call = newCall }
        if newRecording != recording { recording = newRecording }
        if newScreen != screenRecording { screenRecording = newScreen }
        if siri != siriActive { siriActive = siri }
    }

    /// The app a microphone user belongs to. Browsers and calling apps record from helper
    /// processes ("Google Chrome Helper"), so those are matched to their app by bundle ID.
    private static func owningApp(for user: ActivityProbe.MicUser) -> (bundleID: String, name: String)? {
        if let running = NSRunningApplication(processIdentifier: user.pid),
           running.activationPolicy == .regular, let id = running.bundleIdentifier {
            return (id, running.localizedName ?? id)
        }
        let id = user.bundleID
        if id.hasPrefix("com.apple.WebKit") {
            return ("com.apple.Safari", "Safari")
        }
        for known in callApps.union(browsers) where id.hasPrefix(known + ".") {
            let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: known)
                .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? known
            return (known, name)
        }
        return nil
    }

    /// Stops macOS's screen recording, the same as pressing ⌃⌘Esc. Needs Accessibility access.
    static func stopScreenRecording() {
        guard AXIsProcessTrusted() else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: down)
            event?.flags = [.maskCommand, .maskControl]
            event?.post(tap: .cghidEventTap)
        }
    }
}

enum ActivityProbe {
    struct MicUser: Sendable {
        let pid: pid_t
        let bundleID: String
    }

    struct WindowSignals: Sendable {
        var screenRecording = false
        var siriShowing = false
    }

    /// Every process recording from a microphone right now (macOS 14.2 and later).
    static func microphoneUsers() -> [MicUser] {
        guard #available(macOS 14.2, *) else { return [] }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }

        var users: [MicUser] = []
        for object in objects {
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningInput,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(object, &inputAddress, 0, nil, &runningSize, &running) == noErr,
                  running != 0 else { continue }

            var pidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(object, &pidAddress, 0, nil, &pidSize, &pid) == noErr else { continue }

            var bundleAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyBundleID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var bundle: Unmanaged<CFString>?
            var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var bundleID = ""
            if AudioObjectGetPropertyData(object, &bundleAddress, 0, nil, &bundleSize, &bundle) == noErr,
               let value = bundle?.takeRetainedValue() {
                bundleID = value as String
            }
            users.append(MicUser(pid: pid, bundleID: bundleID))
        }
        return users
    }

    /// Reads the small windows in the menu bar: the Stop button macOS shows while it records the
    /// screen, and Siri's window. Only owner names and sizes, which need no permission.
    static func menuBarSignals() -> WindowSignals {
        var signals = WindowSignals()
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return signals }
        for window in list {
            let owner = (window[kCGWindowOwnerName as String] as? String) ?? ""
            let alpha = (window[kCGWindowAlpha as String] as? Double) ?? 1
            guard alpha > 0.01 else { continue }
            let bounds = (window[kCGWindowBounds as String] as? [String: Double]) ?? [:]
            let y = bounds["Y"] ?? 999
            let height = bounds["Height"] ?? 999
            let width = bounds["Width"] ?? 999
            if owner == "screencaptureui" && y < 40 && height <= 40 && width <= 80 {
                signals.screenRecording = true
            } else if owner.localizedCaseInsensitiveContains("siri") && width > 40 && height > 20 {
                signals.siriShowing = true
            }
        }
        return signals
    }
}
