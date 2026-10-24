// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// Timer: quick presets, or the running countdown.
struct TimerTab: View {
    let app: AppModel

    var body: some View {
        let scale = IslandLayout.contentScale(app)
        if app.timer.isActive || app.timer.finished {
            RunningTimerView(app: app, scale: scale)
        } else {
            TimerPresets(timer: app.timer, scale: scale)
        }
    }
}

private struct TimerPresets: View {
    let timer: TimerService
    let scale: CGFloat
    private let presets: [(minutes: Double, label: String)] = [
        (1, "min"), (3, "min"), (5, "min"), (10, "min"), (15, "min"), (25, "focus"),
    ]

    init(timer: TimerService, scale: CGFloat) {
        self.timer = timer
        self.scale = scale
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * scale) {
            Text("Start a timer")
                .font(.system(size: max(10, 11 * scale), weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 8 * scale) {
                ForEach(presets.indices, id: \.self) { index in
                    let preset = presets[index]
                    Button {
                        withAnimation(.snappy) { timer.start(minutes: preset.minutes) }
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(Int(preset.minutes))")
                                .font(.system(size: 22 * scale, weight: .bold, design: .rounded))
                            Text(preset.label)
                                .font(.system(size: max(9, 10 * scale), weight: .medium))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        .frame(maxWidth: .infinity, minHeight: 74 * scale)
                        .background(RoundedRectangle(cornerRadius: 16 * scale, style: .continuous).fill(Color.white.opacity(0.08)))
                        .contentShape(RoundedRectangle(cornerRadius: 16 * scale, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct RunningTimerView: View {
    let app: AppModel
    let scale: CGFloat

    var body: some View {
        let timer = app.timer
        let s = scale
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            HStack(spacing: 18 * s) {
                ZStack {
                    Circle().stroke(Color.orange.opacity(0.18), lineWidth: 7 * s)
                    Circle()
                        .trim(from: 0, to: timer.progress(at: context.date))
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 7 * s, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.5), value: timer.progress(at: context.date))
                    Image(systemName: timer.finished ? "bell.fill" : "timer")
                        .font(.system(size: 20 * s, weight: .bold))
                        .foregroundStyle(.orange)
                        .symbolEffect(.bounce, value: timer.finished)
                }
                .frame(width: 78 * s, height: 78 * s)

                VStack(alignment: .leading, spacing: 2) {
                    Text(timer.finished ? "Time's up!" : formatClock(timer.remaining(at: context.date)))
                        .font(.system(size: 36 * s, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                    Text(timer.finished ? "Nice work" : (timer.isPaused ? "Paused" : "Timer running"))
                        .font(.system(size: max(10, 12 * s)))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer(minLength: 0)

                if timer.finished {
                    IconButton(symbol: "checkmark", size: 46 * s, fill: .orange) {
                        withAnimation(.snappy) {
                            timer.dismissFinished()
                            app.alerts.dismiss(.timer)
                        }
                    }
                } else {
                    HStack(spacing: 10 * s) {
                        Button {
                            timer.add(minutes: 1)
                        } label: {
                            Text("+1 min")
                                .font(.system(size: max(10.5, 12 * s), weight: .semibold))
                                .padding(.horizontal, 12 * s)
                                .frame(height: 34 * s)
                                .background(Capsule().fill(Color.white.opacity(0.12)))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressableStyle())
                        IconButton(symbol: timer.isPaused ? "play.fill" : "pause.fill", size: 46 * s, fill: .orange.opacity(0.9)) {
                            withAnimation(.snappy) { timer.togglePause() }
                        }
                        IconButton(symbol: "xmark", size: 46 * s) {
                            withAnimation(.snappy) { timer.cancel() }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}
