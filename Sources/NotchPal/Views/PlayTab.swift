// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// Games: pick a game and a difficulty, then play right inside the island.
struct PlayTab: View {
    let app: AppModel
    @Bindable private var settings: SettingsStore

    @Environment(\.isIslandPicture) private var isPicture

    init(app: AppModel) {
        self.app = app
        _settings = Bindable(wrappedValue: app.settings)
    }

    var body: some View {
        let hub = app.games
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(GameKind.allCases) { kind in
                    GameChip(kind: kind, selected: hub.selected == kind) {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                            hub.selected = kind
                        }
                    }
                }
                Spacer(minLength: 6)
                Text("Best \(hub.current.best)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .monospacedDigit()
                if isPicture {
                    Text(settings.difficulty.label)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 22)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                } else {
                    Picker("Difficulty", selection: $settings.difficulty) {
                        ForEach(Difficulty.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 168)
                }
            }
            GameCanvas(hub: hub)
        }
        .onChange(of: settings.difficulty) {
            hub.resetAll()
        }
    }
}

private struct GameChip: View {
    let kind: GameKind
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 11, weight: .semibold))
                if selected {
                    Text(kind.title)
                        .font(.system(size: 11, weight: .semibold))
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(Color.white.opacity(selected ? 0.18 : 0.07)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .opacity(selected ? 1 : 0.7)
        .help("\(kind.title): \(kind.hint)")
    }
}

/// Draws the selected game every frame while it's running.
private struct GameCanvas: View {
    let hub: GameHub

    var body: some View {
        let game = hub.current
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: nil, paused: game.phase != .running)) { context in
                Canvas { graphics, size in
                    game.step(to: context.date, size: size)
                    game.draw(in: &graphics, size: size)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                game.tap(at: location, in: proxy.size)
            }
            .onContinuousHover { hover in
                switch hover {
                case .active(let point):
                    game.pointer(at: point, in: proxy.size)
                case .ended:
                    game.pointer(at: nil, in: proxy.size)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .id(hub.selected)
    }
}
