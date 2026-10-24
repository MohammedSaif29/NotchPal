// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// Home: the music player with volume and speaker picker, AirDrop, and the battery.
/// Everything scales with the island's Width and Length settings.
struct HomeTab: View {
    let app: AppModel

    var body: some View {
        let scale = IslandLayout.contentScale(app)
        let compact = IslandLayout.isCompactBody(app)
        HStack(spacing: 10 * scale) {
            MusicCard(app: app, scale: scale)
            VStack(spacing: 7 * scale) {
                AirDropCard(scale: scale, showHint: !compact)
                if app.power.hasBattery {
                    BatteryCard(app: app, compact: compact, scale: scale)
                        .frame(height: max(30, (compact ? 36 : 50) * scale))
                }
            }
            .frame(width: 106 * scale)
        }
    }
}

struct MusicCard: View {
    let app: AppModel
    /// 1 is the standard size; smaller or bigger islands scale everything.
    var scale: CGFloat = 1

    var body: some View {
        let music = app.nowPlaying
        let tint = app.accent
        let s = scale
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10 * s) {
                ArtworkThumb(artwork: music.artwork, appIcon: music.appIcon, size: 52 * s)
                    .shadow(color: tint.opacity(music.artwork == nil ? 0 : 0.4), radius: 10 * s, y: 3 * s)
                    .overlay(alignment: .bottomTrailing) {
                        // Which app is playing: Spotify, Music, YouTube in Chrome…
                        if app.settings.showSourceBadge, music.artwork != nil, let icon = music.appIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18 * s, height: 18 * s)
                                .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                                .offset(x: 5 * s, y: 5 * s)
                                .allowsHitTesting(false)
                        }
                    }
                    .onTapGesture { music.openSourceApp() }
                    .help(openHint(music))
                VStack(alignment: .leading, spacing: 2 * s) {
                    Text(music.track?.title ?? "Nothing playing")
                        .font(.system(size: max(11, 13 * s), weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle(music))
                        .font(.system(size: max(9.5, 11 * s)))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if music.track != nil {
                    VisualizerBars(playing: music.isPlaying, tint: tint, height: 16 * s)
                }
            }

            Spacer(minLength: 6 * s)
            SeekBar(music: music, tint: tint, scale: s)
            Spacer(minLength: 6 * s)

            HStack(spacing: 10 * s) {
                HStack(spacing: 8 * s) {
                    IconButton(symbol: "backward.fill", size: 30 * s) { music.previous() }
                    IconButton(symbol: music.isPlaying ? "pause.fill" : "play.fill", size: 36 * s,
                               fill: .white, foreground: .black) {
                        withAnimation(.snappy) { music.togglePlayPause() }
                    }
                    IconButton(symbol: "forward.fill", size: 30 * s) { music.next() }
                }
                .disabled(music.track == nil)
                .opacity(music.track == nil ? 0.4 : 1)

                Spacer(minLength: 6)

                VolumeControl(audio: app.audio, scale: s)
                    .frame(maxWidth: 170 * s)
            }
        }
        .padding(12 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18 * s, style: .continuous).fill(Color.white.opacity(0.07)))
    }

    private func subtitle(_ music: NowPlayingService) -> String {
        guard let track = music.track else { return "Play something in any app" }
        let parts = [track.artist, track.album].filter { !$0.isEmpty }
        if parts.isEmpty {
            return track.appName ?? ""
        }
        return parts.joined(separator: " · ")
    }

    private func openHint(_ music: NowPlayingService) -> String {
        guard let name = music.track?.appName else { return "" }
        return "Open \(name)"
    }
}

/// Progress bar you can drag to jump around in the song.
struct SeekBar: View {
    let music: NowPlayingService
    let tint: Color
    let scale: CGFloat
    // View state is stored as plain State values instead of with the @State attribute.
    // On macOS 27, @State became a macro that needs a plugin only full Xcode has,
    // and this way NotchPal still builds with just the Command Line Tools.
    private let scrub = State<Double?>(initialValue: nil)

    init(music: NowPlayingService, tint: Color, scale: CGFloat = 1) {
        self.music = music
        self.tint = tint
        self.scale = scale
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let duration = music.track?.duration ?? 0
            let live = music.track?.position(at: context.date, playing: music.isPlaying) ?? 0
            let position = scrub.wrappedValue.map { $0 * duration } ?? live
            HStack(spacing: 8 * scale) {
                Text(formatClock(position, roundUp: false))
                    .frame(width: 34 * max(1, scale), alignment: .leading)
                CapsuleSlider(
                    value: duration > 0 ? position / duration : 0,
                    tint: tint,
                    onChange: { scrub.wrappedValue = $0 },
                    onCommit: { fraction in
                        if duration > 0 {
                            music.seek(to: fraction * duration)
                        }
                        scrub.wrappedValue = nil
                    }
                )
                Text("-" + formatClock(max(0, duration - position)))
                    .frame(width: 38 * max(1, scale), alignment: .trailing)
            }
            .font(.system(size: max(9, 10 * scale), weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.55))
            .opacity(duration > 0 ? 1 : 0.35)
            .allowsHitTesting(duration > 0)
        }
    }
}

/// Volume slider, mute, and a menu to pick speakers or AirPods.
struct VolumeControl: View {
    let audio: AudioService
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 6 * scale) {
            Button { audio.toggleMute() } label: {
                Image(systemName: volumeSymbol)
                    .font(.system(size: 11 * scale, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 18 * scale, height: 18 * scale)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .help(audio.isMuted ? "Unmute" : "Mute")

            CapsuleSlider(value: audio.isMuted ? 0 : audio.volume, tint: .white, onChange: { audio.setVolume($0) })

            OutputMenu(audio: audio, scale: scale)
        }
        .foregroundStyle(.white.opacity(0.85))
    }

    private var volumeSymbol: String {
        if audio.isMuted || audio.volume < 0.01 { return "speaker.slash.fill" }
        if audio.volume < 0.34 { return "speaker.wave.1.fill" }
        if audio.volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

struct OutputMenu: View {
    let audio: AudioService
    var scale: CGFloat = 1

    var body: some View {
        Menu {
            Section("Play sound through") {
                ForEach(audio.outputs) { output in
                    Button {
                        audio.select(output)
                    } label: {
                        if output.id == audio.current?.id {
                            Label(output.name, systemImage: "checkmark")
                        } else {
                            Text(output.name)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: audio.current?.symbol ?? "hifispeaker")
                .font(.system(size: 12 * scale, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(audio.current?.name ?? "Sound output")
    }
}

struct AirDropCard: View {
    var scale: CGFloat = 1
    var showHint = true
    // View state is stored as plain State values instead of with the @State attribute.
    // On macOS 27, @State became a macro that needs a plugin only full Xcode has,
    // and this way NotchPal still builds with just the Command Line Tools.
    private let hovering = State(initialValue: false)

    init(scale: CGFloat = 1, showHint: Bool = true) {
        self.scale = scale
        self.showHint = showHint
    }

    var body: some View {
        let corner = 16 * scale
        Button {
            // Let the button finish its click before the file picker takes over.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { AirDrop.pickAndSend() }
            }
        } label: {
            VStack(spacing: 4 * scale) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 19 * scale, weight: .semibold))
                    .symbolEffect(.variableColor.iterative, isActive: hovering.wrappedValue)
                Text("AirDrop")
                    .font(.system(size: max(10.5, 12 * scale), weight: .semibold))
                if showHint {
                    Text("Drop files or click")
                        .font(.system(size: max(9, 9.5 * scale)))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.white.opacity(hovering.wrappedValue ? 0.38 : 0.18),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
            .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering.wrappedValue = $0 }
    }
}
