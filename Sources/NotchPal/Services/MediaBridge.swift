// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

/// What the media helper reports.
enum MediaBridgeMessage {
    case ready
    case failed(String)
    case nothingPlaying
    case info(MediaBridgeInfo)
}

enum ArtworkUpdate {
    case unchanged
    case cleared
    case image(NSImage, Color?)
}

struct MediaBridgeInfo {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var elapsed: Double
    var timestamp: Date
    var rate: Double
    var playing: Bool
    var pid: Int32
    var artwork: ArtworkUpdate
}

/// Runs the tiny Now Playing helper and talks to it over pipes.
///
/// Since macOS 15.4, only Apple's own programs may read what's playing. /usr/bin/perl is
/// one of them, so NotchPal asks perl to load a small library (NotchPalMediaBridge) that
/// reads the system's Now Playing info and prints one JSON line per change.
/// Commands (play/pause, skip, seek) go the other way on stdin.
@MainActor
final class MediaBridge {
    var onMessage: (@MainActor (MediaBridgeMessage) -> Void)?
    /// Called when the helper can't run on this Mac, so the app can fall back.
    var onUnavailable: (@MainActor () -> Void)?

    private var process: Process?
    private var input: FileHandle?
    private var crashes: [Date] = []
    private var stopping = false

    var isRunning: Bool { process != nil }

    @discardableResult
    func start() -> Bool {
        guard process == nil,
              let script = Bundle.main.url(forResource: "media-bridge", withExtension: "pl"),
              let library = Bundle.main.url(forResource: "libNotchPalMediaBridge", withExtension: "dylib")
        else {
            onUnavailable?()
            return false
        }

        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        helper.arguments = [script.path, library.path]
        let output = Pipe()
        let commands = Pipe()
        helper.standardOutput = output
        helper.standardInput = commands
        helper.standardError = FileHandle.nullDevice

        let reader = BridgeLineReader { [weak self] message in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.onMessage?(message) }
            }
        }
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            reader.consume(data)
        }
        helper.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.helperEnded(status: status) }
            }
        }

        do {
            try helper.run()
        } catch {
            NSLog("NotchPal: media helper failed to start: \(error.localizedDescription)")
            onUnavailable?()
            return false
        }
        process = helper
        input = commands.fileHandleForWriting
        return true
    }

    func stop() {
        stopping = true
        process?.terminate()
        process = nil
        input = nil
    }

    /// Sends one command line to the helper. Returns false if the helper isn't running.
    @discardableResult
    func send(_ line: String) -> Bool {
        guard let input, let data = (line + "\n").data(using: .utf8) else { return false }
        do {
            try input.write(contentsOf: data)
            return true
        } catch {
            return false
        }
    }

    private func helperEnded(status: Int32) {
        process = nil
        input = nil
        guard !stopping else { return }

        // Exit codes 2 and 3 mean MediaRemote itself is missing: retrying won't help.
        let now = Date()
        crashes = crashes.filter { now.timeIntervalSince($0) < 60 } + [now]
        if status == 2 || status == 3 || crashes.count >= 3 {
            NSLog("NotchPal: media helper unavailable (status \(status)), using Spotify/Music fallback")
            onUnavailable?()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            MainActor.assumeIsolated { _ = self?.start() }
        }
    }
}

/// Splits the helper's output into lines and decodes them, off the main thread.
/// Artwork decoding happens here too, so big images never stall the UI.
private final class BridgeLineReader: @unchecked Sendable {
    private var buffer = Data()
    private let deliver: @Sendable (MediaBridgeMessage) -> Void

    init(deliver: @escaping @Sendable (MediaBridgeMessage) -> Void) {
        self.deliver = deliver
    }

    func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
            if let message = Self.decode(line) {
                deliver(message)
            }
        }
    }

    private static func decode(_ line: Data) -> MediaBridgeMessage? {
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let type = object["type"] as? String
        else { return nil }

        switch type {
        case "ready":
            return .ready
        case "none":
            return .nothingPlaying
        case "error":
            return .failed(object["message"] as? String ?? "")
        case "info":
            var artwork = ArtworkUpdate.unchanged
            if let encoded = object["artwork"] as? String {
                if encoded.isEmpty {
                    artwork = .cleared
                } else if let data = Data(base64Encoded: encoded), let image = NSImage(data: data) {
                    artwork = .image(image, image.vibrantAverageColor())
                }
            }
            let stamp = object["timestamp"] as? Double ?? Date().timeIntervalSince1970
            let info = MediaBridgeInfo(
                title: object["title"] as? String ?? "",
                artist: object["artist"] as? String ?? "",
                album: object["album"] as? String ?? "",
                duration: object["duration"] as? Double ?? 0,
                elapsed: object["elapsed"] as? Double ?? 0,
                timestamp: Date(timeIntervalSince1970: stamp),
                rate: object["rate"] as? Double ?? 0,
                playing: object["playing"] as? Bool ?? false,
                pid: Int32(object["pid"] as? Int ?? 0),
                artwork: artwork
            )
            return .info(info)
        default:
            return nil
        }
    }
}

extension NSImage {
    /// A bright version of the image's average colour, used to tint the island like iOS does.
    func vibrantAverageColor() -> Color? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drew: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drew else { return nil }

        var red = 0.0, green = 0.0, blue = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            red += Double(pixels[index])
            green += Double(pixels[index + 1])
            blue += Double(pixels[index + 2])
        }
        let total = Double(side * side) * 255
        let average = NSColor(srgbRed: red / total, green: green / total, blue: blue / total, alpha: 1)

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        if saturation < 0.12 {
            return Color(white: 0.92) // Black-and-white artwork: stay neutral.
        }
        let vivid = NSColor(hue: hue,
                            saturation: min(1, max(saturation, 0.5) * 1.1),
                            brightness: max(brightness, 0.9),
                            alpha: 1)
        return Color(nsColor: vivid)
    }
}
