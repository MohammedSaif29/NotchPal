// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// The closed island with something to show: little "wings" either side of the camera.
struct CompactWingsView: View {
    let app: AppModel
    let size: CGSize

    var body: some View {
        let notch = app.state.notch
        let wing = max(0, (size.width - notch.width) / 2)
        HStack(spacing: 0) {
            leading.frame(width: wing)
            Color.clear.frame(width: notch.width)
            trailing.frame(width: wing)
        }
        .frame(height: size.height)
        .foregroundStyle(.white)
        .font(.system(size: 12, weight: .semibold, design: .rounded))
    }

    @ViewBuilder
    private var leading: some View {
        let music = app.nowPlaying
        switch IslandLayout.compactKind(app) {
        case .music:
            ArtworkThumb(artwork: app.settings.showArtworkInNotch ? music.artwork : nil,
                         appIcon: music.appIcon,
                         size: max(16, min(22, app.state.notch.height - 9)))
                .opacity(music.isPlaying ? 1 : 0.55)
                .scaleEffect(music.isPlaying ? 1 : 0.88)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: music.isPlaying)
        case .timer:
            if app.timer.finished {
                Image(systemName: "bell.fill")
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse)
            } else {
                Image(systemName: "timer")
                    .foregroundStyle(.orange)
            }
        case .ambient:
            if app.settings.pet {
                NotchPet(app: app)
            } else if IslandLayout.showsBattery(app) {
                BatteryWing(app: app, side: .leading)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        let music = app.nowPlaying
        // The privacy dots sit beside whatever else is here, never on top of it.
        HStack(spacing: 6) {
            switch IslandLayout.compactKind(app) {
            case .music:
                if app.settings.showVisualizer {
                    VisualizerBars(playing: music.isPlaying, tint: app.accent)
                } else {
                    Image(systemName: music.isPlaying ? "play.fill" : "pause.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(app.accent)
                        .contentTransition(.symbolEffect(.replace))
                }
            case .timer:
                if app.timer.finished {
                    Text("Done").foregroundStyle(.orange)
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(formatClock(app.timer.remaining(at: context.date)))
                            .monospacedDigit()
                            .foregroundStyle(.orange)
                            .contentTransition(.numericText(countsDown: true))
                    }
                }
            case .ambient:
                if IslandLayout.showsBattery(app) {
                    BatteryWing(app: app, side: .trailing)
                }
            }
            if IslandLayout.showsPrivacyDots(app) {
                PrivacyDots(camera: app.privacy.cameraInUse, mic: app.privacy.micInUse)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// iPhone-style dots: green while a camera is on, orange while a microphone is listening.
struct PrivacyDots: View {
    let camera: Bool
    let mic: Bool

    var body: some View {
        HStack(spacing: 3) {
            if mic {
                Circle().fill(Color.orange).frame(width: 6, height: 6)
            }
            if camera {
                Circle().fill(Color.green).frame(width: 6, height: 6)
            }
        }
        .shadow(color: (camera ? Color.green : Color.orange).opacity(0.7), radius: 3)
        .help(camera && mic ? "Camera and microphone in use" : (camera ? "Camera in use" : "Microphone in use"))
    }
}
