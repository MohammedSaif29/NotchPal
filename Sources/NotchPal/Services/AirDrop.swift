// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import UniformTypeIdentifiers

/// Sends files through AirDrop, using Apple's public sharing API.
enum AirDrop {
    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [URL] = []

        func add(_ url: URL) {
            lock.lock()
            stored.append(url)
            lock.unlock()
        }

        var urls: [URL] {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
    }

    /// Files dragged onto the notch.
    static func send(_ providers: [NSItemProvider]) {
        let collected = Collected()
        let group = DispatchGroup()

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { collected.add(url) }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let urls = collected.urls
            MainActor.assumeIsolated { send(urls: urls) }
        }
    }

    @MainActor
    static func send(urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate()
        service.perform(withItems: urls)
    }

    /// Lets you pick files to AirDrop when you can't drag them.
    @MainActor
    static func pickAndSend() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "AirDrop"
        panel.message = "Choose files to send with AirDrop"
        NSApp.activate()
        if panel.runModal() == .OK {
            send(urls: panel.urls)
        }
    }
}
