// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

/// An app's icon by bundle ID, remembered so it's only looked up once.
@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = icon
        return icon
    }
}

/// How long something has been going: 0:42, 12:04, 1:02:09.
func formatElapsed(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, secs)
        : String(format: "%d:%02d", minutes, secs)
}

/// The left side of a call, recording or screen-recording pill.
struct LiveLeading: View {
    let item: LiveItem
    let size: CGFloat

    var body: some View {
        switch item.kind {
        case .screenRecording:
            Image(systemName: "record.circle.fill")
                .font(.system(size: size * 0.8, weight: .semibold))
                .foregroundStyle(.red)
                .symbolEffect(.pulse)
        case .call:
            HStack(spacing: 4) {
                if let icon = AppIcons.icon(for: item.bundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: size, height: size)
                }
                Image(systemName: "phone.fill")
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundStyle(.green)
            }
        case .recording:
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                    .font(.system(size: size * 0.7, weight: .bold))
                    .foregroundStyle(.red)
                    .symbolEffect(.variableColor.iterative)
                if let icon = AppIcons.icon(for: item.bundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: size * 0.85, height: size * 0.85)
                }
            }
        case .music, .timer:
            EmptyView()
        }
    }
}

/// The right side of a call, recording or screen-recording pill: a running clock.
struct LiveClock: View {
    let item: LiveItem

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(formatElapsed(context.date.timeIntervalSince(item.since ?? context.date)))
                .monospacedDigit()
                .foregroundStyle(Color(nsColor: item.tint))
                .contentTransition(.numericText())
        }
    }
}

/// The second little island beside the notch, for a second live activity.
struct ActivityBubble: View {
    let app: AppModel
    let item: LiveItem
    let diameter: CGFloat

    var body: some View {
        ZStack {
            switch item.kind {
            case .timer:
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    ZStack {
                        Circle().stroke(Color.orange.opacity(0.25), lineWidth: 2.5)
                        Circle()
                            .trim(from: 0, to: app.timer.progress(at: context.date))
                            .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: app.timer.finished ? "bell.fill" : "timer")
                            .font(.system(size: diameter * 0.3, weight: .bold))
                            .foregroundStyle(.orange)
                    }
                    .padding(6)
                }
            case .music:
                ArtworkThumb(artwork: app.nowPlaying.artwork, appIcon: app.nowPlaying.appIcon,
                             size: diameter - 12)
                    .clipShape(Circle())
                    .opacity(app.nowPlaying.isPlaying ? 1 : 0.6)
            case .call:
                ZStack {
                    Circle().fill(Color.green.opacity(0.22)).padding(5)
                    Image(systemName: "phone.fill")
                        .font(.system(size: diameter * 0.32, weight: .bold))
                        .foregroundStyle(.green)
                }
            case .recording:
                Image(systemName: "waveform")
                    .font(.system(size: diameter * 0.38, weight: .bold))
                    .foregroundStyle(.red)
                    .symbolEffect(.variableColor.iterative)
            case .screenRecording:
                Image(systemName: "record.circle.fill")
                    .font(.system(size: diameter * 0.45, weight: .semibold))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse)
            }
        }
        .frame(width: diameter + 8, height: diameter)
        .background(NotchShape(topRadius: 4, bottomRadius: diameter / 2).fill(Color.black))
        .contentShape(Rectangle())
        .help(item.title)
    }
}

/// Apple's "island mitosis": the second island splits off the notch like a water droplet. A
/// stretchy black neck joins the two while they pull apart, then snaps. The same in reverse
/// when it merges back.
struct DropletSplit: ViewModifier, Animatable {
    /// 0 inside the island, 1 fully split off.
    var progress: Double
    let islandWidth: CGFloat
    let islandHeight: CGFloat
    let topRadius: CGFloat
    let bottomRadius: CGFloat
    let diameter: CGFloat
    /// Draw the stretchy neck. Off for glass islands, where a black neck wouldn't match.
    let neck: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private var bubbleWidth: CGFloat { diameter + 8 }

    /// Where the bubble's centre is, from the island's centre.
    private var offset: CGFloat {
        let inside = islandWidth / 2 - bubbleWidth / 2 - 4
        let outside = islandWidth / 2 + IslandLayout.bubbleGap + bubbleWidth / 2
        return inside + (outside - inside) * CGFloat(progress)
    }

    func body(content: Content) -> some View {
        let canvasWidth = islandWidth + (bubbleWidth + IslandLayout.bubbleGap) * 2 + 40
        let canvasHeight = max(islandHeight, diameter) + 16
        ZStack(alignment: .top) {
            if neck && progress > 0.02 && progress < 0.98 {
                Canvas { graphics, size in
                    let center = size.width / 2
                    let island = CGRect(x: center - islandWidth / 2, y: 0, width: islandWidth, height: islandHeight)
                    // Only outside the island, so the neck never covers what's in the wings.
                    graphics.clip(to: NotchShape(topRadius: topRadius, bottomRadius: bottomRadius).path(in: island),
                                  options: .inverse)
                    graphics.addFilter(.alphaThreshold(min: 0.5, color: .black))
                    // The blur melts the two shapes together; less of it as they part, so the neck snaps.
                    graphics.addFilter(.blur(radius: 9 * (1 - progress) + 1))
                    graphics.drawLayer { layer in
                        let end = CGRect(x: island.maxX - 46, y: -20, width: 46, height: islandHeight + 20)
                        layer.fill(Path(roundedRect: end, cornerRadius: min(bottomRadius, 16)), with: .color(.black))
                        let bubbleX = center + offset - bubbleWidth / 2
                        let bubble = CGRect(x: bubbleX, y: -20, width: bubbleWidth, height: diameter + 20)
                        layer.fill(Path(roundedRect: bubble, cornerRadius: diameter / 2), with: .color(.black))
                    }
                }
                .frame(width: canvasWidth, height: canvasHeight)
                .allowsHitTesting(false)
            }
            content
                .scaleEffect(0.55 + 0.45 * CGFloat(progress), anchor: .top)
                .opacity(min(1, progress * 2.5))
                .offset(x: offset)
        }
        .frame(width: canvasWidth, height: canvasHeight, alignment: .top)
    }
}

/// A slim row at the top of the open island for a call, recording or screen recording, like
/// an expanded Live Activity on Apple's island.
struct LiveActivityRow: View {
    let app: AppModel
    let item: LiveItem

    var body: some View {
        HStack(spacing: 10) {
            LiveLeading(item: item, size: 18)
            Text(item.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            LiveClock(item: item)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            Spacer(minLength: 6)
            switch item.kind {
            case .screenRecording:
                if AXIsProcessTrusted() {
                    pill("Stop", symbol: "stop.fill", color: .red) {
                        ActivityMonitor.stopScreenRecording()
                    }
                } else {
                    Text("Press ⌃⌘Esc to stop")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.55))
                }
            case .call, .recording:
                pill("Show", symbol: "arrow.up.forward.app", color: .white.opacity(0.18)) {
                    if let id = item.bundleID,
                       let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
                        running.activate()
                        app.closeIsland()
                    }
                }
            case .music, .timer:
                EmptyView()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Capsule().fill(Color(nsColor: item.tint).opacity(0.14)))
    }

    private func pill(_ title: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(Capsule().fill(color))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}
