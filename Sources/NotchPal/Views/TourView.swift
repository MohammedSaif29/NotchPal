// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

/// Which tour: everything for someone new, or what changed for someone who just updated.
enum TourKind: Equatable {
    case welcome
    case whatsNew(version: String)
}

struct TourState: Equatable {
    var kind: TourKind
    var step = 0
}

/// Something a tour card can do besides moving on.
enum TourAction: Equatable {
    case trySearch
    case askSiri
    case openSettings
}

struct TourStep: Equatable {
    var symbol: String
    var colors: [Color]
    var title: String
    var body: String
    /// Key caps to show, like ["⌥", "Space"].
    var keys: [String] = []
    var action: TourAction?
    var actionTitle: String = ""
}

/// The tour's cards. Every new version can add its own "What's new" cards here.
@MainActor
enum Tours {
    /// Versions that have What's new cards. Updating to one of these shows them once.
    static let versionsWithNews: Set<String> = ["0.7.0"]

    static func steps(_ kind: TourKind, app: AppModel) -> [TourStep] {
        switch kind {
        case .welcome: return welcome(app)
        case .whatsNew: return whatsNew(app)
        }
    }

    private static func openStep(_ app: AppModel) -> TourStep {
        app.settings.openOnHover
            ? TourStep(symbol: "cursorarrow.motionlines", colors: [GlowColors.cyan, GlowColors.blue],
                       title: "Hover to open",
                       body: "Move your pointer onto the notch and it opens. Music, calendar, the mirror, notes, timers and games all live inside.")
            : TourStep(symbol: "cursorarrow.click.2", colors: [GlowColors.cyan, GlowColors.blue],
                       title: "Click the notch to open it",
                       body: "Or swipe down on it with two fingers, and push up to close. Music, calendar, the mirror, notes, timers and games all live inside.")
    }

    private static func searchStep(_ app: AppModel) -> TourStep {
        TourStep(symbol: "magnifyingglass", colors: [GlowColors.purple, GlowColors.pink],
                 title: "Search from anywhere",
                 body: "Apps, files, settings, maths and quick commands like “timer 10m” or “note buy milk”.",
                 keys: shortcutKeys(app.settings.searchShortcut), action: .trySearch, actionTitle: "Try it")
    }

    private static func aiStep() -> TourStep {
        AppleIntelligence.isAvailable
            ? TourStep(symbol: "sparkles", colors: IntelligenceColors.all,
                       title: "Ask Apple Intelligence",
                       body: "Type a question in search and the answer appears right in the notch, privately on your Mac. Tap the rainbow orb for Siri.",
                       action: .askSiri, actionTitle: "Ask Siri")
            : TourStep(symbol: "sparkles", colors: IntelligenceColors.all,
                       title: "Ask Siri, Claude or ChatGPT",
                       body: "Type a question in search, or tap the rainbow orb to talk to Siri. The notch glows while it listens.",
                       action: .askSiri, actionTitle: "Ask Siri")
    }

    private static func liveStep() -> TourStep {
        TourStep(symbol: "phone.fill", colors: [GlowColors.green, GlowColors.mint],
                 title: "Live Activities",
                 body: "Calls, recordings, music and timers show in the notch with a running clock. A second one splits off like a droplet.")
    }

    private static func welcome(_ app: AppModel) -> [TourStep] {
        [
            TourStep(symbol: "sparkles", colors: [GlowColors.pink, GlowColors.purple, GlowColors.cyan],
                     title: "Hi, I'm NotchPal",
                     body: "Your notch is alive now. Here's a quick tour of what it can do. Use the arrow keys or the buttons below."),
            openStep(app),
            searchStep(app),
            aiStep(),
            liveStep(),
            TourStep(symbol: "paintpalette.fill", colors: [GlowColors.orange, GlowColors.pink],
                     title: "Make it yours",
                     body: "Glow, glass, size, battery style, Pal the pet and more in Settings, from the capsule in your menu bar.",
                     action: .openSettings, actionTitle: "Open Settings"),
        ]
    }

    private static func whatsNew(_ app: AppModel) -> [TourStep] {
        [
            TourStep(symbol: "sparkles", colors: [GlowColors.pink, GlowColors.purple, GlowColors.cyan],
                     title: "What's new in NotchPal \(app.updates.currentVersion)",
                     body: "Your notch now works like the Dynamic Island on Apple's newest MacBook Pro. Here's what changed."),
            TourStep(symbol: "drop.fill", colors: [GlowColors.cyan, GlowColors.blue],
                     title: "A floating island",
                     body: app.settings.openOnHover
                        ? "When it opens, the island splits off and floats just below the notch like a droplet, then melts back in."
                        : "Click the notch or swipe down on it: the island splits off and floats below like a droplet. Push up to close. Hovering just makes it bulge."),
            searchStep(app),
            aiStep(),
            liveStep(),
            TourStep(symbol: "slider.horizontal.3", colors: [GlowColors.orange, GlowColors.pink],
                     title: "Glass, your way",
                     body: "A new slider from ultra clear to fully tinted, and text that stays readable over bright windows.",
                     action: .openSettings, actionTitle: "Open Settings"),
        ]
    }

    static func shortcutKeys(_ shortcut: SearchShortcut) -> [String] {
        switch shortcut {
        case .optionSpace: return ["⌥", "Space"]
        case .controlSpace: return ["⌃", "Space"]
        case .optionCommandSpace: return ["⌥", "⌘", "Space"]
        case .shiftCommandSpace: return ["⇧", "⌘", "Space"]
        case .off: return []
        }
    }
}

/// One tour card, in the notch.
struct TourView: View {
    let app: AppModel
    var floating = true

    static let size = CGSize(width: 460, height: 214)

    var body: some View {
        let state = app.state.tour ?? TourState(kind: .welcome)
        let steps = Tours.steps(state.kind, app: app)
        let index = min(state.step, steps.count - 1)
        let step = steps[index]

        VStack(spacing: 0) {
            Color.clear.frame(height: floating ? 0 : max(app.state.notch.height - 6, 0))
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle().fill(LinearGradient(colors: step.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .opacity(0.9)
                    Image(systemName: step.symbol)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: index)
                }
                .frame(width: 46, height: 46)
                .shadow(color: (step.colors.first ?? .white).opacity(0.5), radius: 8)

                VStack(alignment: .leading, spacing: 6) {
                    Text(step.title)
                        .font(.system(size: 16, weight: .semibold))
                    Text(step.body)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                    if !step.keys.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(Array(step.keys.enumerated()), id: \.offset) { offset, key in
                                if offset > 0 {
                                    Text("+").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
                                }
                                KeyCap(label: key)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            .id(index)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .padding(.horizontal, 20)
            .padding(.top, 18)

            Spacer(minLength: 6)

            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    ForEach(0..<steps.count, id: \.self) { dot in
                        Capsule()
                            .fill(Color.white.opacity(dot == index ? 0.9 : 0.25))
                            .frame(width: dot == index ? 16 : 6, height: 6)
                    }
                }
                Spacer()
                if index < steps.count - 1 {
                    button("Skip", primary: false) { app.endTour() }
                }
                if index > 0 {
                    button("Back", primary: false) { app.moveTour(by: -1) }
                }
                if let action = step.action {
                    button(step.actionTitle, primary: false) { app.runTourAction(action) }
                }
                button(index == steps.count - 1 ? "Done" : "Next", primary: true) {
                    if index == steps.count - 1 { app.endTour() } else { app.moveTour(by: 1) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .foregroundStyle(.white)
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: index)
    }

    private func button(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .frame(height: 26)
                .foregroundStyle(primary ? Color.black : Color.white)
                .background(Capsule().fill(primary ? Color.white : Color.white.opacity(0.14)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

/// A keyboard key, like the ones printed on your Mac.
struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: label.count > 1 ? 12 : 15, weight: .semibold, design: .rounded))
            .padding(.horizontal, label.count > 1 ? 14 : 0)
            .frame(minWidth: 30, minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.2), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 0, y: 2)
    }
}
