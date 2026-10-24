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
                    text: "Allow NotchPal under Privacy & Security → Accessibility. It's only used to read the unread counts on your Dock icons.",
                    button: "Open Settings"
                ) {
                    badges.requestAccess()
                    badges.openAccessibilitySettings()
                }
            } else if badges.badges.isEmpty {
                InboxMessage(symbol: "checkmark.seal.fill", title: "All caught up",
                             text: "No unread notifications in your Dock apps.", button: nil) {}
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
    let action: () -> Void

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
            if let button {
                Button(action: action) {
                    Text(button)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(Capsule().fill(Color.white.opacity(0.16)))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
            }
        }
    }
}
