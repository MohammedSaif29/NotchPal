// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

/// "Save Pictures of My Island…": draws the island exactly as it looks right now, in a few of its
/// states, and saves them as sharp PNG pictures you can share. Nothing is uploaded anywhere.
@MainActor
enum IslandPictures {
    static func save(app: AppModel) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Save Here"
        panel.message = "Choose where to save pictures of your island. NotchPal makes a \"NotchPal Pictures\" folder there."
        NSApp.activate()
        guard panel.runModal() == .OK, let chosen = panel.url else { return }

        let folder = chosen.appendingPathComponent("NotchPal Pictures", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let originalTab = app.state.tab
        defer { app.state.tab = originalTab }

        // The open island on a few tabs. The Mirror is left out, so your face is never in a picture.
        let tabs: [(IslandTab, String)] = [(.home, "1-music"), (.calendar, "2-calendar"), (.play, "3-games"),
                                           (.timer, "4-timer"), (.apps, "5-apps")]
        for (tab, name) in tabs where app.settings.visibleTabs.contains(tab) {
            app.state.tab = tab
            write(OpenIslandPicture(app: app), to: folder.appendingPathComponent("\(name).png"))
        }
        if IslandLayout.content(app) == .compact {
            write(ClosedIslandPicture(app: app), to: folder.appendingPathComponent("6-closed-notch.png"))
        }
        if app.power.hasBattery {
            write(BatteryStylesPicture(app: app), to: folder.appendingPathComponent("7-battery-styles.png"))
        }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    private static func write(_ view: some View, to url: URL) {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return }
        try? data.write(to: url)
    }
}

/// A plain backdrop, like a wallpaper, with the island hanging from the top edge of the screen.
private struct PictureBackdrop<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 56)
            .padding(.bottom, 48)
            .background(
                LinearGradient(colors: [Color(red: 0.10, green: 0.11, blue: 0.22),
                                        Color(red: 0.30, green: 0.16, blue: 0.38)],
                               startPoint: .top, endPoint: .bottom)
            )
    }
}

private struct OpenIslandPicture: View {
    let app: AppModel

    var body: some View {
        let notch = app.state.notch
        let size = CGSize(width: max(CGFloat(app.settings.openWidth), notch.width + 300),
                          height: notch.height + IslandLayout.openHeight(app))
        let shape = NotchShape(topRadius: 14, bottomRadius: CGFloat(app.settings.cornerRadius))
        PictureBackdrop {
            ZStack(alignment: .top) {
                shape.fill(Color.black)
                ExpandedView(app: app)
                    .frame(width: size.width, height: size.height, alignment: .top)
            }
            .frame(width: size.width + 28, height: size.height)
            .clipShape(shape)
            .foregroundStyle(.white)
        }
    }
}

private struct ClosedIslandPicture: View {
    let app: AppModel

    var body: some View {
        let geometry = IslandLayout.geometry(app)
        let shape = NotchShape(topRadius: geometry.topRadius, bottomRadius: geometry.bottomRadius)
        PictureBackdrop {
            ZStack(alignment: .top) {
                shape.fill(Color.black)
                CompactWingsView(app: app, size: geometry.size)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
            .frame(width: geometry.size.width + geometry.topRadius * 2, height: geometry.size.height)
            .clipShape(shape)
            .padding(.horizontal, 120)
        }
    }
}

/// The clean battery styles side by side, with your real battery level.
private struct BatteryStylesPicture: View {
    let app: AppModel

    var body: some View {
        PictureBackdrop {
            HStack(spacing: 18) {
                ForEach([BatteryStyle.ring, .pill, .percent, .minimal]) { style in
                    VStack(spacing: 10) {
                        BatteryBadge(reading: BatteryReading.current(app, style: style), size: 18)
                            .frame(width: 104, height: 44)
                            .background(Capsule().fill(Color.black))
                        Text(style.label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
            .padding(.top, 40)
        }
    }
}
