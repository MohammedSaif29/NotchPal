// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// The open island: your chosen widgets as tabs on both sides of the camera, settings on the right,
/// and the selected widget below.
struct ExpandedView: View {
    let app: AppModel
    @Namespace private var tabSpace

    init(app: AppModel) {
        self.app = app
    }

    var body: some View {
        let state = app.state
        let tabs = app.settings.visibleTabs
        let width = IslandLayout.geometry(app).size.width
        // Room on each side of the camera, inside the island's padding.
        let side = max(40, (width - state.notch.width) / 2 - 20)
        let layout = TabLayout.make(count: tabs.count, side: side)
        let leftTabs = Array(tabs.prefix(layout.left))
        let rightTabs = Array(tabs.dropFirst(layout.left))
        let showClock = side - CGFloat(rightTabs.count) * layout.slot - TabLayout.gear > 52

        VStack(spacing: 8) {
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(leftTabs) { tab in
                        tabButton(tab, slot: layout.slot)
                    }
                }
                Spacer(minLength: state.notch.width + 12)
                HStack(spacing: 0) {
                    ForEach(rightTabs) { tab in
                        tabButton(tab, slot: layout.slot)
                    }
                    if showClock {
                        ClockLabel()
                            .padding(.horizontal, 6)
                    }
                    Button {
                        app.closeIsland()
                        app.openSettings?()
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: TabLayout.gear - 2, height: 24)
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressableStyle())
                    .help("Settings")
                }
            }
            .frame(height: max(state.notch.height, 28))

            Group {
                switch state.tab {
                case .home: HomeTab(app: app)
                case .calendar: CalendarTab(app: app)
                case .camera: CameraTab(app: app)
                case .apps: AppsTab(app: app)
                case .inbox: InboxTab(app: app)
                case .notes: NotesTab(app: app)
                case .timer: TimerTab(app: app)
                case .play: PlayTab(app: app)
                }
            }
            .id(state.tab)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .foregroundStyle(.white)
    }

    private func tabButton(_ tab: IslandTab, slot: CGFloat) -> some View {
        TabButton(tab: tab, selected: app.state.tab == tab, badge: badgeCount(for: tab),
                  slot: slot, namespace: tabSpace) {
            if tab != .play {
                app.games.pauseAll()
            }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                app.state.tab = tab
            }
        }
    }

    /// A little red dot on the Notifications tab when something is unread.
    private func badgeCount(for tab: IslandTab) -> Bool {
        tab == .inbox && !app.badges.badges.isEmpty
    }
}

/// Splits the tabs between the two sides of the camera so they're as roomy as possible.
private struct TabLayout {
    let left: Int
    let slot: CGFloat

    /// Width kept for the settings button on the right.
    static let gear: CGFloat = 28

    static func make(count: Int, side: CGFloat) -> TabLayout {
        let total = max(1, count)
        var best = TabLayout(left: total, slot: 0)
        // Try every split, preferring more tabs on the left when it's a tie.
        for left in stride(from: total, through: 1, by: -1) {
            let right = total - left
            let leftSlot = side / CGFloat(left)
            let rightSlot = right > 0 ? (side - gear) / CGFloat(right) : CGFloat.greatestFiniteMagnitude
            let slot = min(32, leftSlot, rightSlot)
            if slot > best.slot {
                best = TabLayout(left: left, slot: slot)
            }
        }
        return TabLayout(left: best.left, slot: max(22, best.slot))
    }
}

private struct TabButton: View {
    let tab: IslandTab
    let selected: Bool
    let badge: Bool
    let slot: CGFloat
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: slot - 2, height: 24)
                .background {
                    if selected {
                        Capsule()
                            .fill(Color.white.opacity(0.18))
                            .matchedGeometryEffect(id: "selectedTab", in: namespace)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if badge {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                            .offset(x: -4, y: 3)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .frame(width: slot)
        .opacity(selected ? 1 : 0.55)
        .help(tab.title)
    }
}
