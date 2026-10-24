// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Observation
import UniformTypeIdentifiers

/// Your favourite apps, launchable from the notch.
@MainActor
@Observable
final class AppShelf {
    struct Item: Identifiable, Equatable {
        let path: String
        let name: String

        var id: String { path }
    }

    private(set) var items: [Item]

    private static let storageKey = "favoriteApps"
    private static let starterApps = [
        "com.apple.finder", "com.apple.Safari", "com.apple.Music",
        "com.apple.Notes", "com.apple.systempreferences", "com.apple.calculator",
    ]

    init() {
        let paths: [String]
        if let saved = UserDefaults.standard.stringArray(forKey: Self.storageKey) {
            paths = saved.filter { FileManager.default.fileExists(atPath: $0) }
        } else {
            paths = Self.starterApps.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)?.path }
        }
        var loaded: [Item] = []
        for path in paths {
            loaded.append(Self.makeItem(path))
        }
        items = loaded
    }

    func icon(for item: Item) -> NSImage {
        NSWorkspace.shared.icon(forFile: item.path)
    }

    func launch(_ item: Item) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: item.path),
                                           configuration: NSWorkspace.OpenConfiguration())
    }

    /// Lets you pick apps to add.
    func pickApps() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add to Notch"
        panel.message = "Choose apps to show in the notch"
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        var updated = items
        for url in panel.urls where !updated.contains(where: { $0.path == url.path }) {
            updated.append(Self.makeItem(url.path))
        }
        items = updated
        save()
    }

    func remove(_ item: Item) {
        items.removeAll { $0.path == item.path }
        save()
    }

    func move(_ item: Item, by offset: Int) {
        guard let index = items.firstIndex(of: item) else { return }
        let target = min(max(0, index + offset), items.count - 1)
        guard target != index else { return }
        var updated = items
        updated.remove(at: index)
        updated.insert(item, at: target)
        items = updated
        save()
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.path), forKey: Self.storageKey)
    }

    private static func makeItem(_ path: String) -> Item {
        var name = FileManager.default.displayName(atPath: path)
        if name.hasSuffix(".app") {
            name = String(name.dropLast(4))
        }
        return Item(path: path, name: name)
    }
}

/// A quick scratchpad that's saved automatically.
@MainActor
@Observable
final class NotesStore {
    var text: String {
        didSet { scheduleSave() }
    }

    @ObservationIgnored private var saveWork: DispatchWorkItem?

    init() {
        text = UserDefaults.standard.string(forKey: "quickNote") ?? ""
    }

    func clear() {
        text = ""
    }

    func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let value = text
        let work = DispatchWorkItem {
            UserDefaults.standard.set(value, forKey: "quickNote")
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}
