// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

/// The settings window that pops up on the main screen.
@MainActor
final class SettingsWindowController {
    private let app: AppModel
    private var window: NSWindow?

    init(app: AppModel) {
        self.app = app
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(app: app))
            let created = NSWindow(contentViewController: hosting)
            created.title = "NotchPal Settings"
            created.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            created.titlebarAppearsTransparent = false
            created.toolbar = NSToolbar(identifier: "NotchPalSettings")
            created.toolbarStyle = .unified
            created.isReleasedWhenClosed = false
            created.setContentSize(NSSize(width: 760, height: 540))
            created.minSize = NSSize(width: 700, height: 480)
            created.center()
            window = created
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
