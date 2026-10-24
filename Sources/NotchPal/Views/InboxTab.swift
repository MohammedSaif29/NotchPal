// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// Notifications: unread counts from the apps in your Dock (Messages, WhatsApp, Mail, Slack…).
struct InboxTab: View {
    let app: AppModel

    var body: some View {
        let badges = app.badges
        Group {
            if !badges.enabled {
                InboxMessage(
                    symbol: "bell.badge.fill",
                    title: "See unread messages in the notch",
                    text: "NotchPal can show the unread counts from your Dock icons and pop up when new messages arrive.",
                    button: "Turn On"
                ) {
                    app.settings.badgesEnabled = true
                    badges.setEnabled(true)
                    if !badges.trusted { badges.requestAccess() }
                }
            } else if !badges.trusted {
                InboxMessage(
                    symbol: "hand.raised.fill",
                    title: "One permission needed",
                    text: "Switch on NotchPal in Privacy & Security → Accessibility. Already on? Click Fix It: macOS forgets the permission each time NotchPal is updated.",
                    button: badges.fixing ? "Fixing…" : "Fix It",
                    secondButton: "Open Settings",
                    secondAction: {
                        badges.requestAccess()
                        badges.openAccessibilitySettings()
                    }
                ) {
                    badges.fixPermission()
                }
            } else if !badges.dockReadable {
                InboxMessage(
                    symbol: "exclamationmark.triangle.fill",
                    title: "Can't read the Dock yet",
                    text: "macOS hasn't let NotchPal see your Dock icons. Click Fix It, then switch NotchPal on in the list that opens.",
                    button: badges.fixing ? "Fixing…" : "Fix It"
                ) {
                    badges.fixPermission()
                }
            } else if badges.badges.isEmpty {
                InboxMessage(symbol: "checkmark.seal.fill", title: "All caught up",
                             text: "Apps show up here when their Dock icon has a red badge. Keep the app in your Dock, and check its badges are on in System Settings → Notifications.",
                             button: nil) {}
            } else {
                BadgeGrid(app: app)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct BadgeGrid: View {
    let app: AppModel

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 8)]
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(app.badges.badges) { badge in
                    Button {
                        app.badges.open(badge)
                        app.closeIsland()
                    } label: {
                        HStack(spacing: 10) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: badge.path))
                                .resizable()
                                .frame(width: 30, height: 30)
                            Text(badge.name)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(badge.count)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .padding(.horizontal, 7)
                                .frame(minWidth: 22, minHeight: 20)
                                .background(Capsule().fill(Color.red))
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.07)))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct InboxMessage: View {
    let symbol: String
    let title: String
    let text: String
    let button: String?
    var secondButton: String?
    var secondAction: (() -> Void)?
    let action: () -> Void

    init(symbol: String, title: String, text: String, button: String?,
         secondButton: String? = nil, secondAction: (() -> Void)? = nil, action: @escaping () -> Void) {
        self.symbol = symbol
        self.title = title
        self.text = text
        self.button = button
        self.secondButton = secondButton
        self.secondAction = secondAction
        self.action = action
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content(showIcon: true)
            content(showIcon: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(showIcon: Bool) -> some View {
        VStack(spacing: 7) {
            if showIcon {
                Image(systemName: symbol)
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.8))
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HStack(spacing: 8) {
                if let button {
                    capsuleButton(button, filled: true, action: action)
                }
                if let secondButton, let secondAction {
                    capsuleButton(secondButton, filled: false, action: secondAction)
                }
            }
        }
    }

    private func capsuleButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(Capsule().fill(Color.white.opacity(filled ? 0.2 : 0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}
