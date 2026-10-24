// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

/// A short alert below the camera: charging, AirPods, a new song, a meeting, a message…
struct AlertView: View {
    let app: AppModel
    let alert: IslandAlert

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: app.state.notch.height)
            HStack(spacing: 12) {
                leading
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                trailing
            }
            .padding(.horizontal, 18)
            .frame(maxHeight: .infinity)
        }
        .foregroundStyle(.white)
    }

    /// The battery on the right of a battery alert, in your style. The bolt is already on the left.
    @ViewBuilder
    private func batteryBadge(level: Int, charging: Bool) -> some View {
        let reading = BatteryReading.make(app, level: level, charging: charging).withoutBolt()
        if reading.style == .emoji {
            BatteryNumber(reading: reading, size: 16)
        } else {
            BatteryBadge(reading: reading, size: 16)
        }
    }

    private var title: String {
        switch alert {
        case .welcome: "NotchPal is ready"
        case .charging: "Charging"
        case .lowBattery: "Low Battery"
        case .device: "Connected"
        case .nowPlaying(let song): song
        case .timerDone: "Time's up!"
        case .event(let name, _, _): name
        case .message(let name, _, _): name
        case .updateAvailable: "Update available"
        case .updating: "Updating NotchPal…"
        case .updated: "NotchPal is up to date"
        case .updateFailed: "The update didn't install"
        }
    }

    private var subtitle: String {
        switch alert {
        case .welcome:
            app.settings.openOnHover ? "Hover over the notch to open it" : "Click the notch to open it"
        case .charging:
            app.power.timeDescription
        case .lowBattery:
            "Plug in soon"
        case .device(let name, _):
            name
        case .nowPlaying:
            app.nowPlaying.track?.artist ?? ""
        case .timerDone:
            "Click to dismiss"
        case .event(_, let minutes, _):
            minutes <= 1 ? "Starts in a minute" : "Starts in \(minutes) minutes"
        case .message(_, let count, _):
            count == "•" || Int(count) == nil ? "New notification" : (count == "1" ? "1 new message" : "\(count) unread")
        case .updateAvailable(let version):
            "NotchPal \(version) is ready"
        case .updating:
            "It restarts by itself in a moment"
        case .updated(let version):
            "Now on version \(version)"
        case .updateFailed:
            "Your current version is untouched"
        }
    }

    @ViewBuilder
    private var leading: some View {
        switch alert {
        case .welcome:
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
        case .charging(let level):
            let reading = BatteryReading.make(app, level: level, charging: true)
            if reading.style == .emoji {
                Text(reading.emoji).font(.system(size: 22))
            } else {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(reading.tint)
            }
        case .lowBattery(let level):
            let reading = BatteryReading.make(app, level: level, charging: false)
            if reading.style == .emoji {
                Text(reading.emoji).font(.system(size: 22))
            } else {
                Image(systemName: "battery.25")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(reading.tint)
            }
        case .device(_, let symbol):
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .regular))
        case .nowPlaying:
            ArtworkThumb(artwork: app.nowPlaying.artwork, appIcon: app.nowPlaying.appIcon, size: 34)
        case .timerDone:
            Image(systemName: "timer")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.orange)
                .symbolEffect(.pulse)
        case .event:
            CalendarGlyph(date: Date(), size: 32)
        case .message(_, _, let path):
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 32, height: 32)
        case .updateAvailable, .updating:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(app.accent)
        case .updated:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.green)
        case .updateFailed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch alert {
        case .charging(let level):
            batteryBadge(level: level, charging: true)
        case .lowBattery(let level):
            batteryBadge(level: level, charging: false)
        case .device:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.green)
        case .nowPlaying:
            VisualizerBars(playing: app.nowPlaying.isPlaying, tint: app.accent)
        case .timerDone:
            Image(systemName: "bell.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.orange)
                .symbolEffect(.pulse)
        case .event(_, _, let link):
            if let link, let url = URL(string: link) {
                Button {
                    NSWorkspace.shared.open(url)
                    app.alerts.dismiss(.calendar)
                } label: {
                    Label("Join", systemImage: "video.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Capsule().fill(Color.green))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
            }
        case .message(_, let count, _):
            Text(count)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .padding(.horizontal, 8)
                .frame(minWidth: 24, minHeight: 22)
                .background(Capsule().fill(Color.red))
        case .updateAvailable:
            Button {
                app.alerts.dismiss(.update)
                app.alerts.show(.updating)
                app.updates.install()
            } label: {
                Text("Update")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .foregroundStyle(.black)
                    .background(Capsule().fill(Color.white))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
        case .updating:
            ProgressView()
                .controlSize(.small)
        case .welcome, .updated, .updateFailed:
            EmptyView()
        }
    }
}

/// Shown while you drag files over the notch.
struct DropHintView: View {
    let notchHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)
            HStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 15, weight: .semibold))
                    .symbolEffect(.variableColor.iterative)
                Text("Drop to AirDrop")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxHeight: .infinity)
        }
    }
}

/// The timer's own little island when music has the main one.
struct TimerBubble: View {
    let timer: TimerService
    let diameter: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            ZStack {
                Circle().stroke(Color.orange.opacity(0.25), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: timer.progress(at: context.date))
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "timer")
                    .font(.system(size: diameter * 0.3, weight: .bold))
                    .foregroundStyle(.orange)
            }
            .padding(6)
        }
        .frame(width: diameter + 8, height: diameter)
        .background(NotchShape(topRadius: 4, bottomRadius: diameter / 2).fill(Color.black))
        .contentShape(Rectangle())
    }
}
