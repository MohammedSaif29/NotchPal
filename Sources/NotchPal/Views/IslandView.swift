// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI
import UniformTypeIdentifiers

/// The island. Sits at the top centre of the panel and springs between shapes as one blob,
/// with the timer bubble splitting off beside it when two things are live.
struct IslandView: View {
    let app: AppModel

    var body: some View {
        let content = IslandLayout.content(app)
        let geometry = IslandLayout.geometry(app)
        let expanded = content == .expanded
        let look = IslandLook.current(app, expanded: expanded)
        let shape = NotchShape(topRadius: geometry.topRadius, bottomRadius: geometry.bottomRadius)
        let islandWidth = geometry.size.width + geometry.topRadius * 2
        let motion = app.settings.motion.spring
        let shadow = app.settings.shadowStrength

        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                IslandBackground(look: look, shape: shape)
                contentView(content, geometry: geometry)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
            .frame(width: islandWidth, height: geometry.size.height)
            .clipShape(shape)
            .background(
                // Liquid Glass draws its own shadow, and anything behind it would show through,
                // so only solid and frosted islands get this one.
                shape.fill(Color.black)
                    .shadow(color: .black.opacity(0.65 * shadow), radius: 18, y: 8)
                    .opacity(expanded && !look.usesLiquidGlass ? 1 : 0)
            )
            .contentShape(shape)
            .onDrop(of: [UTType.fileURL], isTargeted: dropBinding) { providers in
                AirDrop.send(providers)
                return true
            }

            if geometry.bubble > 0 {
                TimerBubble(timer: app.timer, diameter: geometry.bubble)
                    .opacity(app.settings.closedBrightness)
                    .offset(x: islandWidth / 2 + IslandLayout.bubbleGap + (geometry.bubble + 8) / 2)
                    .onTapGesture { app.openIsland(tab: .timer) }
                    .transition(.scale(scale: 0.2, anchor: .leading).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(motion, value: geometry)
        .animation(motion, value: content)
        .animation(.easeInOut(duration: 0.25), value: look)
        .environment(\.colorScheme, .dark)
    }

    /// Icons and text are dimmed to your Brightness settings. The island itself stays black.
    @ViewBuilder
    private func contentView(_ content: IslandContent, geometry: IslandGeometry) -> some View {
        let reveal = app.settings.reveal
        switch content {
        case .expanded:
            ExpandedView(app: app)
                .opacity(app.settings.openBrightness)
                .transition(.islandContent(reveal))
        case .drop:
            DropHintView(notchHeight: app.state.notch.height)
                .opacity(app.settings.openBrightness)
                .transition(.islandContent(reveal))
        case .alert(let alert):
            AlertView(app: app, alert: alert)
                .opacity(max(app.settings.closedBrightness, 0.7))
                .contentShape(Rectangle())
                .onTapGesture { open(from: alert) }
                .id(alert)
                .transition(.islandContent(reveal))
        case .compact:
            CompactWingsView(app: app, size: geometry.size)
                .opacity(app.settings.closedBrightness)
                .contentShape(Rectangle())
                .onTapGesture { app.openIsland() }
                .transition(.islandContent(reveal))
        case .idle:
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { app.openIsland() }
        }
    }

    private func open(from alert: IslandAlert) {
        switch alert {
        case .timerDone: app.openIsland(tab: .timer)
        case .nowPlaying: app.openIsland(tab: .home)
        case .event: app.openIsland(tab: .calendar)
        case .message: app.openIsland(tab: .inbox)
        case .updateAvailable, .updateFailed:
            app.settingsNavigation.page = .about
            app.openSettings?()
        case .updating, .updated:
            break
        default: app.openIsland()
        }
    }

    private var dropBinding: Binding<Bool> {
        Binding(get: { app.state.isDropTargeted }, set: { app.state.isDropTargeted = $0 })
    }
}
