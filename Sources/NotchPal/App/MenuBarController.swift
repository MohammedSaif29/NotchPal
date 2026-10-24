// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit

/// The small capsule icon in the menu bar.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let app: AppModel
    private var updateItem: NSMenuItem?

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
        updateItem = addItem(to: menu, title: "Check for Updates…", action: #selector(updates))
        addItem(to: menu, title: "Report a Problem…", action: #selector(reportProblem))
        menu.addItem(.separator())
        addItem(to: menu, title: "Quit NotchPal", action: #selector(quit), key: "q")
        menu.delegate = self
        item.menu = menu
    }

    /// When an update is waiting, the menu offers it by name.
    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            if case .available(let release) = app.updates.status {
                updateItem?.title = "Update to NotchPal \(release.version)…"
            } else {
                updateItem?.title = "Check for Updates…"
            }
        }
    }

    @objc private func updates() {
        if case .available = app.updates.status {
            app.alerts.show(.updating)
            app.updates.install()
        } else {
            app.settingsNavigation.page = .about
            app.openSettings?()
            app.updates.check()
        }
    }

    @discardableResult
    private func addItem(to menu: NSMenu, title: String, action: Selector, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        menu.addItem(entry)
        return entry
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
