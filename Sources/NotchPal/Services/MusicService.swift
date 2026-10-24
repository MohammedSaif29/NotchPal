// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI
import Observation

/// One song (or video) that's playing somewhere on the Mac.
struct NowPlayingTrack: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var elapsed: Double
    /// When `elapsed` was measured.
    var timestamp: Date
    var rate: Double
    var bundleID: String?
    var appName: String?

    /// Where playback is right now, counting forward from the last report.
    func position(at now: Date, playing: Bool) -> Double {
        var value = elapsed
        if playing {
            value += now.timeIntervalSince(timestamp) * (rate > 0 ? rate : 1)
        }
        value = max(0, value)
        return duration > 0 ? min(value, duration) : value
    }

    func isSameSong(as other: NowPlayingTrack) -> Bool {
        title == other.title && artist == other.artist
    }
}

/// Knows what's playing in any app (Spotify, Apple Music, YouTube in a browser, VLC…)
/// with artwork and progress, and can control it.
///
/// Main source: the system's Now Playing info through `MediaBridge`.
/// Fallback (if Apple ever blocks that): Spotify and Apple Music announce their songs
/// with distributed notifications, and NotchPal controls them with AppleScript.
@MainActor
@Observable
final class NowPlayingService {
    enum Source {
        case waiting
        case mediaRemote
        case scripting
    }

    private(set) var track: NowPlayingTrack?
    private(set) var isPlaying = false
    private(set) var artwork: NSImage?
    private(set) var artworkColor: Color?
    private(set) var appIcon: NSImage?
    private(set) var source: Source = .waiting
    /// True for a few seconds after pausing, so the island doesn't vanish instantly.
    private(set) var lingering = false

    var showsActivity: Bool { track != nil && (isPlaying || lingering) }

    /// Called when a new song starts while something was already playing.
    @ObservationIgnored var onSongChange: (@MainActor (NowPlayingTrack) -> Void)?
    /// Apps you've turned off in Settings → Music, by bundle ID.
    @ObservationIgnored var isHidden: @MainActor (String) -> Bool = { _ in false }
    /// Called with each app that plays something, so Settings can list it.
    @ObservationIgnored var onAppSeen: (@MainActor (String) -> Void)?
    /// The latest report from the system, kept so hiding or showing an app applies straight away.
    @ObservationIgnored private var latestInfo: MediaBridgeInfo?
    @ObservationIgnored private var latestArtwork: (image: NSImage, color: Color?)?

    private let bridge = MediaBridge()
    @ObservationIgnored private var scriptObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var scriptPlayer: ScriptPlayer?
    @ObservationIgnored private var lingerWork: DispatchWorkItem?

    func start() {
        listenToScriptablePlayers()
        bridge.onMessage = { [weak self] message in
            self?.handle(message)
        }
        bridge.onUnavailable = { [weak self] in
            guard let self else { return }
            if self.source == .mediaRemote {
                self.source = .waiting
            }
            self.askScriptablePlayers()
        }
        bridge.start()
        // If the system source hasn't answered in a few seconds, ask Spotify and Music directly,
        // so a song that's already playing shows up without waiting for the next one.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            MainActor.assumeIsolated { self?.askScriptablePlayers() }
        }
    }

    /// Apply a change to the hidden apps right away.
    func refilter() {
        if let latestInfo {
            apply(latestInfo)
        }
    }

    func stop() {
        bridge.stop()
    }

    // MARK: Controls

    func togglePlayPause() {
        guard var current = track else { return }
        let now = Date()
        current.elapsed = current.position(at: now, playing: isPlaying)
        current.timestamp = now
        track = current
        // Update the UI straight away; the player confirms a moment later.
        if isPlaying {
            isPlaying = false
            beginLinger()
        } else {
            isPlaying = true
            endLinger()
        }
        send(.togglePlayPause)
    }

    func next() { send(.nextTrack) }

    func previous() { send(.previousTrack) }

    func seek(to seconds: Double) {
        guard var current = track else { return }
        current.elapsed = max(0, seconds)
        current.timestamp = Date()
        track = current
        if source == .mediaRemote, bridge.send(String(format: "seek %.3f", seconds)) {
            return
        }
        scriptPlayer?.seek(to: seconds)
    }

    func openSourceApp() {
        guard let bundleID = track?.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private enum Command: Int {
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5

        var scriptVerb: String {
            switch self {
            case .togglePlayPause: "playpause"
            case .nextTrack: "next track"
            case .previousTrack: "previous track"
            }
        }
    }

    private func send(_ command: Command) {
        if source == .mediaRemote, bridge.send("cmd \(command.rawValue)") {
            return
        }
        scriptPlayer?.run(command.scriptVerb)
    }

    // MARK: System Now Playing

    private func handle(_ message: MediaBridgeMessage) {
        switch message {
        case .ready:
            source = .mediaRemote
        case .failed(let reason):
            NSLog("NotchPal: media helper says: \(reason)")
        case .nothingPlaying:
            source = .mediaRemote
            latestInfo = nil
            latestArtwork = nil
            clear()
        case .info(let info):
            source = .mediaRemote
            // Keep the artwork even while its app is hidden, so showing the app again shows the right picture.
            switch info.artwork {
            case .unchanged:
                break
            case .cleared:
                latestArtwork = nil
            case .image(let image, let color):
                latestArtwork = (image, color)
            }
            latestInfo = info
            apply(info)
        }
    }

    private func clear() {
        update(track: nil, playing: false)
        if artwork != nil { artwork = nil }
        if artworkColor != nil { artworkColor = nil }
        if appIcon != nil { appIcon = nil }
    }

    private func apply(_ info: MediaBridgeInfo) {
        var bundleID: String?
        var appName: String?
        var icon: NSImage?
        if info.pid > 0, let running = NSRunningApplication(processIdentifier: info.pid) {
            let owner = Self.owner(of: running)
            bundleID = owner.bundleID
            appName = owner.name
            icon = owner.icon
        }
        if let bundleID {
            onAppSeen?(bundleID)
            if isHidden(bundleID) {
                clear()
                return
            }
        }
        if artwork !== latestArtwork?.image {
            artwork = latestArtwork?.image
            artworkColor = latestArtwork?.color
        }
        if appIcon == nil || bundleID != track?.bundleID {
            appIcon = icon
        }
        let new = NowPlayingTrack(
            title: info.title,
            artist: info.artist,
            album: info.album,
            duration: info.duration,
            elapsed: info.elapsed,
            timestamp: info.timestamp,
            rate: info.rate,
            bundleID: bundleID,
            appName: appName
        )
        update(track: new, playing: info.playing)
    }

    /// Browsers play media from helper processes. Find the real app around the helper,
    /// so the island shows "Google Chrome" and its icon instead of "Google Chrome Helper".
    private static func owner(of app: NSRunningApplication) -> (bundleID: String?, name: String?, icon: NSImage?) {
        guard let url = app.bundleURL else {
            return (app.bundleIdentifier, app.localizedName, app.icon)
        }
        let parts = url.pathComponents
        if let index = parts.firstIndex(where: { $0.hasSuffix(".app") }), index < parts.count - 1 {
            let outerPath = NSString.path(withComponents: Array(parts[...index]))
            let outer = URL(fileURLWithPath: outerPath)
            return (Bundle(url: outer)?.bundleIdentifier,
                    outer.deletingPathExtension().lastPathComponent,
                    NSWorkspace.shared.icon(forFile: outerPath))
        }
        return (app.bundleIdentifier, app.localizedName, app.icon)
    }

    private func update(track new: NowPlayingTrack?, playing: Bool) {
        let old = track
        if old != new {
            track = new
        }
        let nowPlaying = playing && new != nil
        if isPlaying != nowPlaying {
            if isPlaying && new != nil {
                beginLinger()
            }
            isPlaying = nowPlaying
        }
        if nowPlaying {
            endLinger()
        }
        if let new, nowPlaying, let old, !new.isSameSong(as: old) {
            onSongChange?(new)
        }
    }

    private func beginLinger() {
        lingering = true
        lingerWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.lingering = false }
        }
        lingerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    private func endLinger() {
        lingerWork?.cancel()
        if lingering {
            lingering = false
        }
    }

    // MARK: Fallback: Spotify and Apple Music

    private enum ScriptPlayer: String, CaseIterable {
        case spotify = "Spotify"
        case music = "Music"

        var notificationName: String {
            switch self {
            case .spotify: "com.spotify.client.PlaybackStateChanged"
            case .music: "com.apple.Music.playerInfo"
            }
        }

        var bundleID: String {
            switch self {
            case .spotify: "com.spotify.client"
            case .music: "com.apple.Music"
            }
        }

        func run(_ command: String) {
            var error: NSDictionary?
            NSAppleScript(source: "tell application \"\(rawValue)\" to \(command)")?.executeAndReturnError(&error)
            if let error {
                NSLog("NotchPal: \(rawValue) command failed: \(error)")
            }
        }

        func seek(to seconds: Double) {
            run(String(format: "set player position to %.2f", seconds))
        }

        var isRunning: Bool {
            !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        }

        /// Asks the app what it's playing, without blocking anything. Spotify reports song
        /// length in milliseconds and Music in seconds, so both are turned into seconds.
        func askState(completion: @escaping @MainActor (ScriptedState?) -> Void) {
            let script = """
            tell application "\(rawValue)"
                set s to player state as string
                if s is "stopped" then return "stopped"
                set t to current track
                return s & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & ((duration of t) as string) & linefeed & ((player position) as string)
            end tell
            """
            let durationScale: Double = self == .spotify ? 1000 : 1
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                var state: ScriptedState?
                if (try? process.run()) != nil {
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    state = ScriptedState(String(decoding: data, as: UTF8.self), durationScale: durationScale)
                }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { completion(state) }
                }
            }
        }
    }

    /// What Spotify or Music said it's playing.
    private struct ScriptedState: Sendable {
        var state: String
        var title = ""
        var artist = ""
        var album = ""
        var duration: Double = 0
        var position: Double = 0

        init?(_ text: String, durationScale: Double) {
            let lines = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
            guard let first = lines.first, !first.isEmpty else { return nil }
            // "playing" → "Playing", the way the apps' notifications say it.
            state = first.prefix(1).uppercased() + first.dropFirst()
            guard lines.count >= 6 else { return }
            title = lines[1]
            artist = lines[2]
            album = lines[3]
            duration = (Double(lines[4].replacingOccurrences(of: ",", with: ".")) ?? 0) / durationScale
            position = Double(lines[5].replacingOccurrences(of: ",", with: ".")) ?? 0
        }
    }

    /// Asks Spotify and Music directly, when the system source isn't working. Only apps that are
    /// already open are asked, so this never launches anything.
    private func askScriptablePlayers() {
        guard source != .mediaRemote else { return }
        for player in ScriptPlayer.allCases where player.isRunning {
            player.askState { [weak self] state in
                guard let self, let state, self.source != .mediaRemote else { return }
                self.handleScripted(player: player, state: state.state, title: state.title, artist: state.artist,
                                    album: state.album, duration: state.duration, position: state.position)
            }
        }
    }

    private func listenToScriptablePlayers() {
        guard scriptObservers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        for player in ScriptPlayer.allCases {
            let token = center.addObserver(
                forName: Notification.Name(player.notificationName),
                object: nil,
                queue: .main
            ) { [weak self] note in
                let info = note.userInfo ?? [:]
                let state = info["Player State"] as? String ?? ""
                let title = info["Name"] as? String ?? ""
                let artist = info["Artist"] as? String ?? ""
                let album = info["Album"] as? String ?? ""
                let millis = (info["Duration"] as? Double) ?? (info["Total Time"] as? Double) ?? 0
                let position = (info["Playback Position"] as? Double) ?? 0
                MainActor.assumeIsolated {
                    self?.handleScripted(player: player, state: state, title: title, artist: artist,
                                         album: album, duration: millis / 1000, position: position)
                }
            }
            scriptObservers.append(token)
        }
    }

    private func handleScripted(player: ScriptPlayer, state: String, title: String, artist: String,
                                album: String, duration: Double, position: Double) {
        // The system source is better (artwork, any app), so prefer it when it works.
        guard source != .mediaRemote else { return }
        source = .scripting
        scriptPlayer = player
        onAppSeen?(player.bundleID)
        if isHidden(player.bundleID) {
            clear()
            return
        }

        if state == "Stopped" {
            update(track: nil, playing: false)
            return
        }
        let name = title.isEmpty ? (track?.title ?? "") : title
        guard !name.isEmpty else { return }

        if appIcon == nil || track?.bundleID != player.bundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleID) {
            appIcon = NSWorkspace.shared.icon(forFile: url.path)
        }
        let new = NowPlayingTrack(
            title: name,
            artist: artist,
            album: album,
            duration: duration,
            elapsed: position,
            timestamp: Date(),
            rate: 1,
            bundleID: player.bundleID,
            appName: player.rawValue
        )
        update(track: new, playing: state == "Playing")
    }
}
