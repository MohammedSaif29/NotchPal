// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import CoreGraphics

/// The app that's full screen on the notch's screen.
struct FullScreenApp: Equatable {
    var bundleID: String?
}

/// Notices when an app is full screen on the notch's screen, and which app it is, so the island
/// can step out of the way of a movie or a game.
///
/// Two checks, neither needs a permission:
/// - Full screen with the green button, or full-screen video in Safari, Chrome, TV, QuickTime,
///   IINA and VLC, gets its own Space. macOS's list of Spaces says which kind is showing.
/// - Some games cover the whole screen without a Space. Then the front app's window covers the
///   entire screen, menu bar included, which a normal window can't do.
@MainActor
final class FullScreenWatcher {
    var onChange: (@MainActor (FullScreenApp?) -> Void)?
    private(set) var current: FullScreenApp?

    private var displayID: CGDirectDisplayID?
    private var displayUUID: String?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var checking = false

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.check()
                    // Going full screen animates, so look again once it has settled.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                        MainActor.assumeIsolated { self?.check() }
                    }
                }
            })
        }
        // Games can go full screen without switching apps or Spaces, so also look now and then.
        let tick = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
    }

    /// The screen the island is on.
    func watch(_ screen: NSScreen) {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        displayID = number.map { CGDirectDisplayID($0.uint32Value) }
        displayUUID = displayID.flatMap(FullScreenProbe.uuid(of:))
        check()
    }

    private func check() {
        guard !checking, let displayID else { return }
        checking = true
        let uuid = displayUUID
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let me = ProcessInfo.processInfo.processIdentifier
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let owner = FullScreenProbe.fullScreenOwner(display: displayID, displayUUID: uuid, front: front, ignoring: me)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.finishCheck(owner) }
            }
        }
    }

    private func finishCheck(_ owner: pid_t?) {
        checking = false
        let app = owner.map { FullScreenApp(bundleID: NSRunningApplication(processIdentifier: $0)?.bundleIdentifier) }
        guard current != app else { return }
        current = app
        onChange?(app)
    }
}

/// The checks themselves. Safe to call from any thread.
enum FullScreenProbe {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> UnsafeMutableRawPointer?

    private struct SpaceFunctions: @unchecked Sendable {
        let connection: MainConnection
        let copySpaces: CopyManagedDisplaySpaces
    }

    /// The window server's own list of Spaces. Window managers like yabai read it the same way.
    /// If a future macOS removes it, this check just stops finding anything.
    private static let spaceFunctions: SpaceFunctions? = {
        let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        let everywhere = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        let names = [("SLSMainConnectionID", "SLSCopyManagedDisplaySpaces", skyLight),
                     ("CGSMainConnectionID", "CGSCopyManagedDisplaySpaces", everywhere)]
        for (connectionName, spacesName, handle) in names {
            guard let handle,
                  let connection = dlsym(handle, connectionName),
                  let spaces = dlsym(handle, spacesName)
            else { continue }
            return SpaceFunctions(connection: unsafeBitCast(connection, to: MainConnection.self),
                                  copySpaces: unsafeBitCast(spaces, to: CopyManagedDisplaySpaces.self))
        }
        return nil
    }()

    /// The kind of Space macOS uses for a full-screen app.
    private static let fullScreenSpaceType = 4

    /// The process that's full screen on this display, or nil when nothing is.
    static func fullScreenOwner(display: CGDirectDisplayID, displayUUID: String?, front: pid_t?, ignoring me: pid_t) -> pid_t? {
        let windows = largeWindows(on: display, ignoring: me)
        if spaceIsFullScreen(displayUUID: displayUUID) {
            // The full-screen app's window is the frontmost big window on this screen.
            return windows.first?.owner ?? front
        }
        // A game covering the whole screen, menu bar included, without its own Space.
        if let front, windows.contains(where: { $0.owner == front && $0.coversWholeScreen }) {
            return front
        }
        return nil
    }

    private static func spaceIsFullScreen(displayUUID: String?) -> Bool {
        guard let functions = spaceFunctions,
              let pointer = functions.copySpaces(functions.connection())
        else { return false }
        let list = Unmanaged<CFArray>.fromOpaque(pointer).takeRetainedValue() as NSArray
        guard let displays = list as? [[String: Any]] else { return false }
        for display in displays {
            let identifier = display["Display Identifier"] as? String ?? ""
            // "Main" means all screens share one set of Spaces.
            let matches = identifier == "Main" || displayUUID == nil
                || identifier.caseInsensitiveCompare(displayUUID ?? "") == .orderedSame
            guard matches, let current = display["Current Space"] as? [String: Any] else { continue }
            if (current["type"] as? NSNumber)?.intValue == fullScreenSpaceType {
                return true
            }
        }
        return false
    }

    private struct LargeWindow {
        let owner: pid_t
        let coversWholeScreen: Bool
    }

    /// Normal windows that fill most of this screen, frontmost first.
    private static func largeWindows(on display: CGDirectDisplayID, ignoring me: pid_t) -> [LargeWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        let screen = CGDisplayBounds(display)
        let screenArea = screen.width * screen.height
        guard screenArea > 0 else { return [] }
        var found: [LargeWindow] = []
        for window in list {
            guard let owner = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, owner != me,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  ((window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0.5,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { continue }
            let overlap = rect.intersection(screen)
            guard !overlap.isNull, overlap.width * overlap.height >= screenArea * 0.85 else { continue }
            found.append(LargeWindow(owner: owner, coversWholeScreen: rect.insetBy(dx: -1, dy: -1).contains(screen)))
        }
        return found
    }

    static func uuid(of display: CGDirectDisplayID) -> String? {
        let unmanaged: Unmanaged<CFUUID>? = CGDisplayCreateUUIDFromDisplayID(display)
        guard let uuid = unmanaged?.takeRetainedValue() else { return nil }
        let text: CFString? = CFUUIDCreateString(nil, uuid)
        return text.map { $0 as String }
    }
}
