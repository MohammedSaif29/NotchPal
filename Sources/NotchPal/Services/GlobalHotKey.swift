// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Carbon.HIToolbox

/// A keyboard shortcut that works from any app, like ⌥ Space for search. Uses the system's
/// hot key service, which needs no Accessibility permission.
@MainActor
final class GlobalHotKey {
    var onPress: (@MainActor () -> Void)?

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func register(_ shortcut: SearchShortcut) {
        unregister()
        guard let (keyCode, modifiers) = shortcut.carbon else { return }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x4E50_534B), id: 1) // "NPSK"
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &hotKey)
    }

    func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { hotKey.onPress?() }
            }
            return noErr
        }, 1, &spec, me, &handler)
    }
}

extension SearchShortcut {
    /// The Space key and its modifiers, in the hot key service's terms.
    var carbon: (Int, Int)? {
        let space = kVK_Space
        switch self {
        case .optionSpace: return (space, optionKey)
        case .controlSpace: return (space, controlKey)
        case .optionCommandSpace: return (space, optionKey | cmdKey)
        case .shiftCommandSpace: return (space, shiftKey | cmdKey)
        case .off: return nil
        }
    }
}
