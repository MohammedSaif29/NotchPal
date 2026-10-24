// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// Apps: your favourite apps, one click away. Add more with +, right-click to remove or move.
struct AppsTab: View {
    let app: AppModel
    @Environment(\.isIslandPicture) private var isPicture

    init(app: AppModel) {
        self.app = app
    }

    var body: some View {
        if isPicture {
            grid
                .frame(maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                grid
            }
        }
    }

    private var grid: some View {
        let shelf = app.shelf
        let scale = IslandLayout.contentScale(app)
        let columns = [GridItem(.adaptive(minimum: 58 * scale, maximum: 76 * scale), spacing: 8)]
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(shelf.items) { item in
                AppTile(name: item.name, icon: shelf.icon(for: item), scale: scale) {
                    shelf.launch(item)
                    app.closeIsland()
                }
                .contextMenu {
                    Button("Open") { shelf.launch(item) }
                    Button("Move Left") { shelf.move(item, by: -1) }
                    Button("Move Right") { shelf.move(item, by: 1) }
                    Divider()
                    Button("Remove from Notch") { shelf.remove(item) }
                }
            }
            AddAppTile(scale: scale) {
                app.closeIsland()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { shelf.pickApps() }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AppTile: View {
    let name: String
    let icon: NSImage
    let scale: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40 * scale, height: 40 * scale)
                Text(name)
                    .font(.system(size: max(9, 10 * scale), weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .frame(width: 64 * scale, height: 66 * scale)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .help(name)
    }
}

private struct AddAppTile: View {
    let scale: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 16 * scale, weight: .semibold))
                    .frame(width: 40 * scale, height: 40 * scale)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    )
                Text("Add")
                    .font(.system(size: max(9, 10 * scale), weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(width: 64 * scale, height: 66 * scale)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .help("Add apps to the notch")
    }
}
