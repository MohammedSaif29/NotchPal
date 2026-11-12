// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

private struct IslandPictureKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while NotchPal draws a picture of the island. Native macOS controls (menus, pickers,
    /// scroll views) can't be drawn into a picture, so views show simple look-alikes instead,
    /// and nothing animates in.
    var isIslandPicture: Bool {
        get { self[IslandPictureKey.self] }
        set { self[IslandPictureKey.self] = newValue }
    }
}

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
        panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        NSApp.activate()
        guard panel.runModal() == .OK, let chosen = panel.url else { return }

        let folder = chosen.appendingPathComponent("NotchPal Pictures", isDirectory: true)
        render(app: app, into: folder)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }


    private static func render(app: AppModel, into folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let originalTab = app.state.tab
        let originalQuery = app.search.query
        defer {
            app.state.tab = originalTab
            app.search.query = originalQuery
        }

        // The island floating below the notch, the way it opens when you click.
        if let first = app.settings.visibleTabs.first(where: { $0 != .camera }) {
            app.state.tab = app.settings.visibleTabs.contains(.home) ? .home : first
            let size = CGSize(width: CGFloat(app.settings.openWidth), height: IslandLayout.openHeight(app) + 38)
            write(FloatingPicture(app: app, size: size) { ExpandedView(app: app, floating: true) },
                  to: folder.appendingPathComponent("1-floating-island.png"))
        }
        // Search in the notch, doing a sum.
        app.search.query = "24*7"
        let searchSize = CGSize(width: max(CGFloat(app.settings.openWidth), 580), height: app.search.bodyHeight + 18)
        write(FloatingPicture(app: app, size: searchSize) { SearchView(app: app, floating: true) },
              to: folder.appendingPathComponent("2-search.png"))
        app.search.query = originalQuery
        // The tour's card about search.
        write(FloatingPicture(app: app, size: TourView.size) {
            TourView(app: app, floating: true, shown: TourState(kind: .welcome, step: 2))
        }, to: folder.appendingPathComponent("3-tour.png"))

        // The open island on a few tabs. The Mirror is left out, so your face is never in a picture.
        let tabs: [(IslandTab, String)] = [(.home, "4-music"), (.calendar, "5-calendar"), (.play, "6-games"),
                                           (.timer, "7-timer"), (.apps, "8-apps")]
        for (tab, name) in tabs where app.settings.visibleTabs.contains(tab) {
            app.state.tab = tab
            write(OpenIslandPicture(app: app), to: folder.appendingPathComponent("\(name).png"))
        }
        if IslandLayout.content(app) == .compact {
            write(ClosedIslandPicture(app: app), to: folder.appendingPathComponent("9-closed-notch.png"))
        }
        if app.power.hasBattery {
            write(BatteryStylesPicture(app: app), to: folder.appendingPathComponent("10-battery-styles.png"))
        }
    }

    private static func write(_ view: some View, to url: URL) {
        let renderer = ImageRenderer(content: view
            .environment(\.colorScheme, .dark)
            .environment(\.isIslandPicture, true))
        renderer.scale = 2
        guard let image = renderer.cgImage, let standard = standardColors(image),
              let data = NSBitmapImageRep(cgImage: standard).representation(using: .png, properties: [:])
        else { return }
        try? data.write(to: url)
    }

    /// Album art and app icons can make macOS draw in an HDR colour format, which most image viewers
    /// (and GitHub) show washed out. Redrawing into plain sRGB makes the colours look right everywhere.
    private static func standardColors(_ image: CGImage) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
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
        let size = CGSize(width: max(CGFloat(app.settings.openWidth), notch.width + 260),
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

/// The closed notch with a card floating just below it, like the island after a click.
private struct FloatingPicture<Card: View>: View {
    let app: AppModel
    let size: CGSize
    let card: Card

    init(app: AppModel, size: CGSize, @ViewBuilder card: () -> Card) {
        self.app = app
        self.size = size
        self.card = card()
    }

    var body: some View {
        let geometry = IslandLayout.geometry(app)
        let shape = NotchShape(topRadius: geometry.topRadius, bottomRadius: geometry.bottomRadius)
        let cardShape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        PictureBackdrop {
            VStack(spacing: IslandLayout.cardGap) {
                ZStack(alignment: .top) {
                    shape.fill(Color.black)
                    CompactWingsView(app: app, size: geometry.size)
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                }
                .frame(width: geometry.size.width + geometry.topRadius * 2, height: geometry.size.height)
                .clipShape(shape)
                card
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .background(cardShape.fill(Color.black))
                    .overlay(cardShape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    .clipShape(cardShape)
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
            }
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
