// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

/// Owns the island window: places it on the notch screen, watches the mouse and keyboard,
/// and opens or closes the island.
@MainActor
final class IslandController {
    /// The panel is a fixed, invisible canvas. Only the island inside it is drawn,
    /// and the panel only takes clicks while the mouse is over the island.
    private static let canvas = CGSize(width: 1040, height: 460)

    private let app: AppModel
    private let panel: IslandPanel

    private var screen: NSScreen?
    private var pollTimer: Timer?
    private var keyMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var lastInside = Date.distantPast
    private var hoverStart: Date?
    private var lastMode: IslandMode = .collapsed
    private var menuOpen = false
    private var scrollMonitor: Any?
    private var swipeDistance: CGFloat = 0
    private var swipeFired = false
    private var effectsMouseLeft = false
    private var effectsSeen = false
    private var effectsChecking = false
    private var effectsTicks = 0

    init(app: AppModel) {
        self.app = app

        panel = IslandPanel(contentRect: NSRect(origin: .zero, size: Self.canvas))
        let host = FirstMouseHostingView(rootView: IslandView(app: app))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: Self.canvas)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        reposition()
        panel.orderFrontRegardless()
        startWatchingMouse()
        startWatchingKeys()
        startWatchingMenus()
        startWatchingSwipes()
    }

    /// Puts the panel at the top centre of the screen that has the notch.
    func reposition() {
        let notchScreen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        guard let target = notchScreen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        screen = target
        app.state.notch = NotchGeometry.detect(for: target)

        let frame = target.frame
        let rect = NSRect(
            x: frame.midX - Self.canvas.width / 2,
            y: frame.maxY - Self.canvas.height,
            width: Self.canvas.width,
            height: Self.canvas.height
        )
        panel.setFrame(rect, display: true)
    }

    // MARK: Mouse

    private func startWatchingMouse() {
        // Reading the cursor position needs no permissions, unlike a global event tap.
        let poll = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(poll, forMode: .common)
        pollTimer = poll
    }

    /// The area of the screen that takes the mouse right now, in screen coordinates.
    ///
    /// While the island is closed, only the notch itself reacts. The wings either side are just for
    /// looking at, so clicks go straight through to the menu bar items underneath them.
    private func hitArea(on frame: NSRect) -> NSRect {
        let notch = app.state.notch
        if app.state.mode == .collapsed && IslandLayout.content(app) != .drop {
            if case .alert = IslandLayout.content(app) {
                // Alerts can have buttons (like Join), so they take clicks while they're showing.
            } else {
                // On a Mac without a notch, a thin strip at the top edge, so menu bar items stay clickable.
                let zoneHeight: CGFloat = notch.hasNotch ? max(notch.height, 6) : 5
                return NSRect(x: frame.midX - notch.width / 2, y: frame.maxY - zoneHeight,
                              width: notch.width, height: zoneHeight)
                    .insetBy(dx: -2, dy: -2)
            }
        }
        let geometry = IslandLayout.geometry(app)
        let width = geometry.size.width + geometry.topRadius * 2
        var area = NSRect(x: frame.midX - width / 2, y: frame.maxY - geometry.size.height,
                          width: width, height: geometry.size.height)
        if geometry.bubble > 0 {
            let bubbleWidth = geometry.bubble + 8
            area = area.union(NSRect(x: frame.midX + width / 2 + IslandLayout.bubbleGap,
                                     y: frame.maxY - geometry.bubble,
                                     width: bubbleWidth, height: geometry.bubble))
        }
        return area.insetBy(dx: -4, dy: -4)
    }

    private func tick() {
        guard let screen else { return }
        let inside = hitArea(on: screen.frame).contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }

        let now = Date()
        if inside {
            lastInside = max(lastInside, now)
        }

        watchEffectsPanel(inside: inside, now: now)

        let state = app.state
        switch state.mode {
        case .collapsed:
            if inside {
                state.mode = .peek
                hoverStart = now
            }
        case .peek:
            if !inside && !state.isDropTargeted {
                state.mode = .collapsed
                hoverStart = nil
            } else if inside, app.settings.openOnHover, !state.isDropTargeted,
                      let start = hoverStart, now.timeIntervalSince(start) >= app.settings.hoverDelay {
                app.openIsland()
            }
        case .expanded:
            // More grace mid-game, so a wobbly mouse doesn't end your run.
            let playing = state.tab == .play && app.games.current.phase == .running
            let grace: TimeInterval = playing ? 1.2 : 0.45
            let held = (state.holdOpenUntil.map { now < $0 } ?? false) || state.effectsPanelOpen
            if inside && state.holdOpenUntil != nil {
                state.holdOpenUntil = nil // The mouse arrived, so normal hover rules apply.
            }
            if !inside && !menuOpen && !held && now.timeIntervalSince(lastInside) > grace {
                state.mode = .collapsed
            }
        }

        if state.mode != lastMode {
            modeChanged(from: lastMode, to: state.mode)
            lastMode = state.mode
        }
    }

    private func modeChanged(from old: IslandMode, to new: IslandMode) {
        let haptics = app.settings.haptics
        switch new {
        case .expanded:
            // Opened by a click or from the menu: stay open a moment even if the mouse isn't there yet.
            lastInside = Date().addingTimeInterval(1.5)
            // Take the keyboard (for games and Esc), unless you're busy in NotchPal's Settings window.
            if NSApp.keyWindow == nil || NSApp.keyWindow === panel {
                panel.makeKey()
            }
            app.alerts.dismissTransient()
            if haptics {
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
        case .peek:
            if old == .collapsed && haptics {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        case .collapsed:
            hoverStart = nil
        }
        if old == .expanded && new != .expanded {
            endEffectsWatch()
            app.games.pauseAll()
            app.camera.stop() // Never leave the camera on once the island closes.
            giveBackKeyboard()
        }
    }

    // MARK: Video Effects panel

    /// While macOS's Video Effects panel is open, the island stays open beside it. It goes back
    /// to normal when the panel closes, when you come back to the island, or after two minutes.
    private func watchEffectsPanel(inside: Bool, now: Date) {
        let state = app.state
        guard let opened = state.effectsPanelOpenedAt else {
            if effectsMouseLeft || effectsSeen || effectsTicks > 0 { resetEffectsWatch() }
            return
        }
        if state.mode != .expanded || now.timeIntervalSince(opened) > 120 {
            endEffectsWatch()
            return
        }
        if !inside {
            effectsMouseLeft = true
        } else if effectsMouseLeft {
            endEffectsWatch() // You came back, so normal hover rules apply again.
            return
        }
        effectsTicks += 1
        guard effectsTicks % 20 == 0, !effectsChecking else { return } // About three times a second.
        effectsChecking = true
        let pid = VideoEffectsPanel.controlCenterPID
        let baseline = state.effectsBaseline
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let showing = !VideoEffectsPanel.largeWindows(of: pid).subtracting(baseline).isEmpty
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.effectsPanelChecked(showing: showing) }
            }
        }
    }

    private func effectsPanelChecked(showing: Bool) {
        effectsChecking = false
        guard app.state.effectsPanelOpen else { return }
        if showing {
            effectsSeen = true
        } else if effectsSeen {
            // The panel closed. Stay a moment so you can come back and look.
            endEffectsWatch()
            app.state.holdOpenUntil = Date().addingTimeInterval(3)
        }
    }

    private func endEffectsWatch() {
        if app.state.effectsPanelOpenedAt != nil {
            app.state.effectsPanelOpenedAt = nil
        }
        resetEffectsWatch()
    }

    private func resetEffectsWatch() {
        effectsMouseLeft = false
        effectsSeen = false
        effectsTicks = 0
    }

    /// Hand typing back to whatever app you were using before the island opened.
    private func giveBackKeyboard() {
        guard panel.isKeyWindow else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    /// Keep the island open while one of its menus (like the speaker picker) is showing.
    private func startWatchingMenus() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuOpen = true }
        })
        observers.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.menuOpen = false
                self?.lastInside = Date()
            }
        })
    }

    // MARK: Swipes

    /// Two-finger swipe sideways on the island to change songs, like the iPhone's island.
    private func startWatchingSwipes() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let swipe = SwipeSample(
                dx: event.scrollingDeltaX,
                dy: event.scrollingDeltaY,
                inverted: event.isDirectionInvertedFromDevice,
                precise: event.hasPreciseScrollingDeltas,
                began: event.phase.contains(.began),
                ended: event.phase.contains(.ended) || event.phase.contains(.cancelled),
                momentum: !event.momentumPhase.isEmpty
            )
            let handled = MainActor.assumeIsolated { self?.handleSwipe(swipe) ?? false }
            return handled ? nil : event
        }
    }

    private func handleSwipe(_ swipe: SwipeSample) -> Bool {
        let state = app.state
        guard app.settings.swipeGestures, swipe.precise, app.nowPlaying.track != nil,
              state.mode != .expanded || state.tab == .home
        else { return false }

        if swipe.momentum { return true } // Ignore the coasting after a flick.
        if swipe.began {
            swipeDistance = 0
            swipeFired = false
        }
        if swipe.ended {
            swipeDistance = 0
            swipeFired = false
            return true
        }
        guard abs(swipe.dx) > abs(swipe.dy) else { return false }

        // Measure in the direction the fingers moved, whatever the scrolling preference.
        swipeDistance += swipe.inverted ? -swipe.dx : swipe.dx
        if !swipeFired && abs(swipeDistance) > 45 {
            swipeFired = true
            if swipeDistance < 0 {
                app.nowPlaying.next()
            } else {
                app.nowPlaying.previous()
            }
            if app.settings.haptics {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
        }
        return true
    }

    // MARK: Keyboard

    private func startWatchingKeys() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = event.keyCode
            let handled = MainActor.assumeIsolated { self?.handleKey(code) ?? false }
            return handled ? nil : event
        }
    }

    private func handleKey(_ keyCode: UInt16) -> Bool {
        guard app.state.mode == .expanded else { return false }
        if keyCode == 53 { // Esc
            app.closeIsland()
            return true
        }
        guard app.state.tab == .play else { return false }

        let input: GameInput
        switch keyCode {
        case 49, 36: input = .action      // Space, Return
        case 126, 13: input = .up         // Up arrow, W
        case 125, 1: input = .down        // Down arrow, S
        case 123, 0: input = .left        // Left arrow, A
        case 124, 2: input = .right       // Right arrow, D
        default: return false
        }
        app.games.current.handle(input)
        return true
    }
}

/// The parts of a scroll event a swipe needs.
private struct SwipeSample {
    let dx: CGFloat
    let dy: CGFloat
    let inverted: Bool
    let precise: Bool
    let began: Bool
    let ended: Bool
    let momentum: Bool
}
