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
        let isOpen = content == .expanded || content == .search || content == .tour
        // Floating: the notch keeps its closed shape and content, and the island floats below it.
        let card = IslandLayout.cardSize(app)
        let notchContent = card != nil ? IslandLayout.closedContent(app) : content
        let expanded = isOpen && card == nil
        let look = IslandLook.current(app, expanded: expanded)
        let cardLook = IslandLook.current(app, expanded: true)
        let shape = NotchShape(topRadius: geometry.topRadius, bottomRadius: geometry.bottomRadius)
        let islandWidth = geometry.size.width + geometry.topRadius * 2
        let motion = app.settings.motion.spring
        // A dark shadow under the open island would smother the glow, so it's lighter while glowing.
        let shadow = app.settings.shadowStrength * (app.settings.glowEnabled ? 0.45 : 1)

        ZStack(alignment: .top) {
            IslandGlow(app: app, content: content,
                       size: CGSize(width: islandWidth, height: geometry.size.height),
                       topRadius: geometry.topRadius, bottomRadius: geometry.bottomRadius)

            if app.settings.pointerMagnet && look.style == .black && !isOpen && content != .hidden {
                PointerMagnet(state: app.state, islandWidth: islandWidth, islandHeight: geometry.size.height,
                              topRadius: geometry.topRadius, bottomRadius: geometry.bottomRadius)
            }

            ZStack(alignment: .top) {
                IslandBackground(look: look, shape: shape)
                contentView(notchContent, geometry: geometry)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                    // Over glass, a soft shadow keeps white text and icons readable on bright windows.
                    .shadow(color: .black.opacity(look.shadowsText ? 0.6 : 0), radius: look.shadowsText ? 2.5 : 0, y: 0.5)
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

            if geometry.bubble > 0, let item = IslandLayout.bubbleItem(app) {
                // The second live activity splits off the notch like a droplet, and merges back.
                let split = { (progress: Double) in
                    DropletSplit(progress: progress, islandWidth: islandWidth, islandHeight: geometry.size.height,
                                 topRadius: geometry.topRadius, bottomRadius: geometry.bottomRadius,
                                 diameter: geometry.bubble, neck: look.style == .black)
                }
                ActivityBubble(app: app, item: item, diameter: geometry.bubble)
                    .opacity(app.settings.closedBrightness)
                    .onTapGesture { openBubble(item) }
                    .id(item.id)
                    // The identity state is the bubble fully split off, beside the island.
                    .transition(.modifier(active: split(0), identity: split(1)))
            }

            if let card {
                // The open island splits off the notch and floats below it, like Apple's new MacBook Pro.
                let split = { (progress: Double) in
                    CardSplit(progress: progress, islandWidth: islandWidth, islandHeight: geometry.size.height,
                              topRadius: geometry.topRadius, bottomRadius: geometry.bottomRadius,
                              cardSize: card, neck: look.style == .black && cardLook.style == .black)
                }
                cardView(content)
                    .frame(width: card.width, height: card.height, alignment: .top)
                    .shadow(color: .black.opacity(look.shadowsText || cardLook.shadowsText ? 0.6 : 0), radius: 2.5, y: 0.5)
                    .background(CardBackground(look: cardLook))
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.black)
                            .shadow(color: .black.opacity(0.6 * shadow), radius: 18, y: 8)
                            .opacity(cardLook.usesLiquidGlass ? 0 : 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .transition(.modifier(active: split(0), identity: split(1)))
            }

            if let start = app.state.introStart {
                LaunchIntro(start: start, notch: app.state.notch, light: app.glow.lightBackdrop)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(motion, value: geometry)
        .animation(motion, value: content)
        .animation(motion, value: card)
        .animation(.easeInOut(duration: 0.25), value: look)
        .environment(\.colorScheme, .dark)
    }

    /// What's inside the floating island.
    @ViewBuilder
    private func cardView(_ content: IslandContent) -> some View {
        switch content {
        case .search:
            SearchView(app: app, floating: true)
                .opacity(app.settings.openBrightness)
        case .tour:
            TourView(app: app, floating: true)
                .opacity(app.settings.openBrightness)
        default:
            ExpandedView(app: app, floating: true)
                .opacity(app.settings.openBrightness)
        }
    }

    /// Icons and text are dimmed to your Brightness settings. The island itself stays black.
    @ViewBuilder
    private func contentView(_ content: IslandContent, geometry: IslandGeometry) -> some View {
        let reveal = app.settings.reveal
        switch content {
        case .search:
            SearchView(app: app)
                .opacity(app.settings.openBrightness)
                .transition(.islandContent(reveal))
        case .tour:
            TourView(app: app, floating: false)
                .opacity(app.settings.openBrightness)
                .transition(.islandContent(reveal))
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
        case .hidden:
            Color.clear
        }
    }

    private func openBubble(_ item: LiveItem) {
        switch item.kind {
        case .timer: app.openIsland(tab: .timer)
        case .music: app.openIsland(tab: .home)
        case .call, .recording, .screenRecording: app.openIsland()
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
