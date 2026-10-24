// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit

/// The small capsule icon in the menu bar.
@MainActor
final class MenuBarController: NSObject {
    private let item: NSStatusItem
    private let app: AppModel

    init(app: AppModel) {
        self.app = app
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "NotchPal")

        let menu = NSMenu()
        addItem(to: menu, title: "Open NotchPal", action: #selector(openIsland))
        addItem(to: menu, title: "Play a Game", action: #selector(openGames))
        addItem(to: menu, title: "Start a Timer", action: #selector(openTimer))
        menu.addItem(.separator())
        addItem(to: menu, title: "Settings…", action: #selector(openSettings), key: ",")
        addItem(to: menu, title: "Save Pictures of My Island…", action: #selector(savePictures))
        addItem(to: menu, title: "About NotchPal", action: #selector(openAbout))
        addItem(to: menu, title: "Report a Problem…", action: #selector(reportProblem))
        menu.addItem(.separator())
        addItem(to: menu, title: "Quit NotchPal", action: #selector(quit), key: "q")
        item.menu = menu
    }

    private func addItem(to menu: NSMenu, title: String, action: Selector, key: String = "") {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        menu.addItem(entry)
    }

    @objc private func openIsland() { app.openIsland(tab: .home) }

    @objc private func openGames() { app.openIsland(tab: .play) }

    @objc private func openTimer() { app.openIsland(tab: .timer) }

    @objc private func openSettings() { app.openSettings?() }

    @objc private func openAbout() {
        app.settingsNavigation.page = .about
        app.openSettings?()
    }

    @objc private func reportProblem() { NSWorkspace.shared.open(Credits.reportProblem) }

    @objc private func savePictures() {
        // Let the menu finish closing before the folder picker opens.
        DispatchQueue.main.async {
            MainActor.assumeIsolated { IslandPictures.save(app: self.app) }
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
