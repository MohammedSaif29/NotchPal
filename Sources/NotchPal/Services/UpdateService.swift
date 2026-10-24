// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import CryptoKit
import Observation

/// A NotchPal version published on GitHub.
struct UpdateRelease: Equatable, Sendable {
    let version: String
    let notes: String
    let page: URL
    let download: URL
    /// GitHub's SHA-256 fingerprint of the download, used to check nothing was changed on the way.
    let digest: String?
}

private struct UpdateError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// Updates, like on a phone: NotchPal asks GitHub once a day whether there's a new version, and
/// when you click Update it downloads it, checks it, swaps it in and restarts.
///
/// The only thing sent is a normal request for NotchPal's latest release page on GitHub. Nothing
/// about you or your Mac is included. Switch it off in Settings → About.
@MainActor
@Observable
final class UpdateService {
    typealias Release = UpdateRelease

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading
        case installing
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var lastChecked: Date?

    /// Called when a new version is found by the daily check.
    @ObservationIgnored var onAvailable: (@MainActor (Release) -> Void)?
    /// Called when an update that was started doesn't install.
    @ObservationIgnored var onFailure: (@MainActor (String) -> Void)?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var announced: String?

    private static let latestRelease = URL(string: "https://api.github.com/repos/MohammedSaif29/NotchPal/releases/latest")!
    private static let lastCheckKey = "lastUpdateCheck"
    static let justUpdatedKey = "justUpdatedTo"

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    init() {
        lastChecked = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
    }

    /// Checks once a day while automatic checks are on.
    func setAutomatic(_ on: Bool) {
        timer?.invalidate()
        timer = nil
        guard on else { return }
        let tick = Timer(timeInterval: 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
        // A little after launch, so starting up stays quick.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
    }

    private func checkIfDue() {
        if let lastChecked, Date().timeIntervalSince(lastChecked) < 20 * 60 * 60 {
            return
        }
        check(announce: true)
    }

    /// Asks GitHub for the latest version. `announce` pops up the update alert in the notch.
    func check(announce: Bool = false) {
        switch status {
        case .checking, .downloading, .installing: return
        default: break
        }
        status = .checking
        var request = URLRequest(url: Self.latestRelease, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("NotchPal/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let current = currentVersion
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw UpdateError("GitHub didn't answer. Try again later.")
                }
                let release = try Self.parse(data)
                self.finishCheck(release, current: current, announce: announce)
            } catch {
                self.status = .failed((error as? UpdateError)?.message ?? "Couldn't check for updates. Are you online?")
            }
        }
    }

    private func finishCheck(_ release: Release, current: String, announce: Bool) {
        let now = Date()
        lastChecked = now
        UserDefaults.standard.set(now, forKey: Self.lastCheckKey)
        guard Self.isNewer(release.version, than: current) else {
            status = .upToDate
            return
        }
        status = .available(release)
        if announce && announced != release.version {
            announced = release.version
            onAvailable?(release)
        }
    }

    /// Downloads the new version, checks it, replaces this copy of NotchPal and restarts.
    func install() {
        guard case .available(let release) = status else { return }
        let appURL = Bundle.main.bundleURL
        let folder = appURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: folder.path) else {
            let message = "NotchPal can't update itself in this folder. Move it to Applications, or download the update from GitHub."
            status = .failed(message)
            onFailure?(message)
            return
        }
        status = .downloading
        let bundleID = Bundle.main.bundleIdentifier ?? "com.saif.notchpal"
        Task {
            do {
                let (file, response) = try await URLSession.shared.download(from: release.download)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw UpdateError("The download didn't work. Try again later.")
                }
                self.status = .installing
                let newApp = try await Self.prepare(file, release: release, bundleID: bundleID)
                self.restart(into: newApp, replacing: appURL, version: release.version)
            } catch {
                let message = (error as? UpdateError)?.message ?? "The update didn't install. Your current version is untouched."
                self.status = .failed(message)
                self.onFailure?(message)
            }
        }
    }

    // MARK: Steps

    private static func parse(_ data: Data) throws -> Release {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let pageText = json["html_url"] as? String, let page = URL(string: pageText),
              let assets = json["assets"] as? [[String: Any]],
              let asset = assets.first(where: { (($0["name"] as? String) ?? "").hasPrefix("NotchPal-")
                                              && (($0["name"] as? String) ?? "").hasSuffix(".zip") }),
              let downloadText = asset["browser_download_url"] as? String, let download = URL(string: downloadText)
        else {
            throw UpdateError("The latest release on GitHub doesn't have a NotchPal download.")
        }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return Release(version: version, notes: json["body"] as? String ?? "", page: page,
                       download: download, digest: asset["digest"] as? String)
    }

    /// "0.10.0" is newer than "0.9.2".
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Checks the download's fingerprint, unzips it, and makes sure it really is NotchPal at the
    /// right version with an intact signature. Runs off the main thread.
    private nonisolated static func prepare(_ zip: URL, release: Release, bundleID: String) async throws -> URL {
        guard let digest = release.digest, digest.hasPrefix("sha256:") else {
            throw UpdateError("GitHub didn't give a fingerprint for this download, so NotchPal won't install it. Download it from GitHub instead.")
        }
        let data = try Data(contentsOf: zip)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == digest.dropFirst("sha256:".count).lowercased() else {
            throw UpdateError("The download doesn't match GitHub's fingerprint, so it wasn't installed.")
        }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("NotchPal-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path]) else {
            throw UpdateError("The download couldn't be unzipped.")
        }
        let app = work.appendingPathComponent("NotchPal.app")
        guard let info = Bundle(url: app),
              info.bundleIdentifier == bundleID,
              (info.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) == release.version
        else {
            throw UpdateError("The download isn't the NotchPal version it should be, so it wasn't installed.")
        }
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) else {
            throw UpdateError("The new version's signature is broken, so it wasn't installed.")
        }
        return app
    }

    private nonisolated static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// A tiny helper waits for NotchPal to quit, swaps in the new copy (putting the old one back if
    /// anything goes wrong), and opens it again.
    private func restart(into newApp: URL, replacing current: URL, version: String) {
        let script = """
        pid="$1"; old="$2"; new="$3"; backup="$2.previous"
        while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
        rm -rf "$backup"
        if mv "$old" "$backup"; then
            if mv "$new" "$old"; then rm -rf "$backup"; else mv "$backup" "$old"; fi
        fi
        xattr -dr com.apple.quarantine "$old" 2>/dev/null
        open "$old"
        """
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/bash")
        helper.arguments = ["-c", script, "notchpal-update",
                            String(ProcessInfo.processInfo.processIdentifier), current.path, newApp.path]
        do {
            try helper.run()
        } catch {
            let message = "The update couldn't restart NotchPal. Your current version is untouched."
            status = .failed(message)
            onFailure?(message)
            return
        }
        UserDefaults.standard.set(version, forKey: Self.justUpdatedKey)
        NSApp.terminate(nil)
    }
}
