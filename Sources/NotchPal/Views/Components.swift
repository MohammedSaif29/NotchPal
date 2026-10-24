// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

/// Buttons shrink a little when pressed, like on iPhone.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// A round icon button whose symbol morphs when it changes (play ⇄ pause).
struct IconButton: View {
    let symbol: String
    var size: CGFloat = 32
    var fill: Color = Color.white.opacity(0.12)
    var foreground: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(Circle().fill(fill))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
    }
}

/// An iOS-style slider: a thin capsule that thickens while you hover or drag it.
struct CapsuleSlider: View {
    let value: Double
    var tint: Color = .white
    var onChange: ((Double) -> Void)?
    var onCommit: ((Double) -> Void)?

    // View state is stored as plain State values instead of with the @State attribute.
    // On macOS 27, @State became a macro that needs a plugin only full Xcode has,
    // and this way NotchPal still builds with just the Command Line Tools.
    private let dragValue = State<Double?>(initialValue: nil)
    private let hovering = State(initialValue: false)

    init(value: Double, tint: Color = .white,
         onChange: ((Double) -> Void)? = nil, onCommit: ((Double) -> Void)? = nil) {
        self.value = value
        self.tint = tint
        self.onChange = onChange
        self.onCommit = onCommit
    }

    var body: some View {
        GeometryReader { proxy in
            let shown = min(1, max(0, dragValue.wrappedValue ?? value))
            let active = hovering.wrappedValue || dragValue.wrappedValue != nil
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, proxy.size.width * shown))
            }
            .frame(height: active ? 8 : 5)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let next = min(1, max(0, drag.location.x / max(1, proxy.size.width)))
                        dragValue.wrappedValue = next
                        onChange?(next)
                    }
                    .onEnded { drag in
                        let released = min(1, max(0, drag.location.x / max(1, proxy.size.width)))
                        onCommit?(released)
                        dragValue.wrappedValue = nil
                    }
            )
            .onHover { hovering.wrappedValue = $0 }
            .animation(.easeOut(duration: 0.15), value: active)
        }
        .frame(height: 16)
    }
}

/// Bouncing bars while music plays. When paused they settle down instead of stopping dead.
struct VisualizerBars: View {
    let playing: Bool
    var tint: Color = .white
    var count = 4
    var height: CGFloat = 16

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playing)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(tint)
                        .frame(width: 3, height: playing ? barHeight(index, time) : 3)
                }
            }
            .frame(height: height)
            .animation(.easeOut(duration: 0.3), value: playing)
        }
    }

    private func barHeight(_ index: Int, _ time: Double) -> CGFloat {
        let fast = sin(time * 5.3 + Double(index) * 1.7)
        let slow = sin(time * 3.1 + Double(index) * 0.9)
        return 4 + (height - 4) * CGFloat(abs(fast * 0.6 + slow * 0.4))
    }
}

/// Album art, or the playing app's icon, or a music note.
struct ArtworkThumb: View {
    let artwork: NSImage?
    let appIcon: NSImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [Color(white: 0.3), Color(white: 0.16)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    if let appIcon {
                        Image(nsImage: appIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(size * 0.14)
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.42, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

struct ClockLabel: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(context.date, format: .dateTime.hour().minute())
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

/// Content appears once the island has grown, and disappears quickly, the way the
/// iPhone's island reveals its content. The style is picked in Settings → Look & Glass.
private struct IslandContentReveal: ViewModifier {
    let shown: Bool
    let style: RevealStyle

    func body(content: Content) -> some View {
        switch style {
        case .blur:
            content
                .blur(radius: shown ? 0 : 10)
                .opacity(shown ? 1 : 0)
                .scaleEffect(shown ? 1 : 0.92, anchor: .top)
        case .fade:
            content
                .opacity(shown ? 1 : 0)
        case .slide:
            content
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : -14)
        case .pop:
            content
                .opacity(shown ? 1 : 0)
                .scaleEffect(shown ? 1 : 0.6, anchor: .top)
        }
    }
}

extension AnyTransition {
    @MainActor
    static func islandContent(_ style: RevealStyle) -> AnyTransition {
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let chosen: RevealStyle = reduced ? .fade : style
        let appear: Animation = chosen == .pop
            ? .spring(response: 0.38, dampingFraction: 0.7).delay(0.06)
            : .easeOut(duration: chosen == .fade ? 0.22 : 0.3).delay(0.08)
        return .asymmetric(
            insertion: .modifier(active: IslandContentReveal(shown: false, style: chosen),
                                 identity: IslandContentReveal(shown: true, style: chosen))
                .animation(appear),
            removal: .modifier(active: IslandContentReveal(shown: false, style: chosen),
                               identity: IslandContentReveal(shown: true, style: chosen))
                .animation(.easeIn(duration: 0.12))
        )
    }
}

/// A real macOS menu that pops up at the mouse. SwiftUI's Menu would flatten a button's custom
/// look, so buttons that need both a styled look and a menu use this.
@MainActor
enum IslandMenu {
    struct Item {
        var title: String
        var symbol: String?
        var checked = false
        var action: () -> Void

        init(title: String, symbol: String? = nil, checked: Bool = false, action: @escaping () -> Void) {
            self.title = title
            self.symbol = symbol
            self.checked = checked
            self.action = action
        }
    }

    static func popUp(_ items: [Item], header: String? = nil) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if let header {
            let title = NSMenuItem(title: header, action: nil, keyEquivalent: "")
            title.isEnabled = false
            menu.addItem(title)
        }
        for item in items {
            let entry = ClosureMenuItem(title: item.title, handler: item.action)
            if let symbol = item.symbol {
                entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            }
            entry.state = item.checked ? .on : .off
            menu.addItem(entry)
        }
        _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func fire() {
        handler()
    }
}
