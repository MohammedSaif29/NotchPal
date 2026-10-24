// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

/// Everything that decides how the island's surface looks.
struct IslandLook: Equatable {
    var style: IslandStyle
    var darkness: Double
    var tint: Color?
    var border: Bool
    /// Height of the solid black band at the top that blends into the notch. 0 for none.
    var capHeight: CGFloat = 0

    static let black = IslandLook(style: .black, darkness: 0, tint: nil, border: false)

    /// True when this look is drawn with Apple's Liquid Glass (macOS 26 and later).
    var usesLiquidGlass: Bool {
        (style == .glass || style == .clear) && hasLiquidGlass
    }

    @MainActor
    static func current(_ app: AppModel, expanded: Bool) -> IslandLook {
        let settings = app.settings
        guard settings.style.isGlass, expanded || settings.glassWhenClosed else { return .black }
        let tint: Color?
        switch settings.glassTint {
        case .none: tint = nil
        case .accent: tint = app.accent
        case .custom: tint = Color(hex: settings.glassTintHex)
        }
        let notch = app.state.notch
        let cap: CGFloat = settings.glassBlendTop && notch.hasNotch ? notch.height : 0
        return IslandLook(style: settings.style, darkness: settings.glassDarkness, tint: tint,
                          border: settings.glassBorder, capHeight: cap)
    }
}

/// The island's fill: solid black, or one of the glass styles.
struct IslandBackground: View {
    let look: IslandLook
    let shape: NotchShape

    var body: some View {
        switch look.style {
        case .black:
            shape.fill(Color.black)
        case .glass, .frosted, .clear:
            GlassFill(look: look, shape: shape)
        }
    }
}

/// Real Liquid Glass on macOS 26 and later, frosted glass on older versions.
struct GlassFill: View {
    let look: IslandLook
    let shape: NotchShape

    var body: some View {
        ZStack {
            base
            if let tint = look.tint {
                shape.fill(tint.opacity(look.style == .clear ? 0.12 : 0.2))
            }
            shape.fill(Color.black.opacity(look.darkness))
            if look.capHeight > 0 {
                NotchCap(height: look.capHeight)
                    .clipShape(shape)
            }
            if look.border {
                NotchOutline(topRadius: shape.topRadius, bottomRadius: shape.bottomRadius).stroke(
                    LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0.06)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            }
        }
    }

    #if compiler(>=6.2)
    @ViewBuilder
    private var base: some View {
        if #available(macOS 26.0, *) {
            if look.style == .frosted {
                frosted
            } else {
                LiquidGlassBase(clear: look.style == .clear, shape: shape)
            }
        } else {
            frosted
        }
    }
    #else
    private var base: some View {
        frosted
    }
    #endif

    private var frosted: some View {
        VisualEffectBlur(material: look.style == .clear ? .fullScreenUI : .hudWindow)
            .clipShape(shape)
    }
}

#if compiler(>=6.2)
@available(macOS 26.0, *)
private struct LiquidGlassBase: View {
    let clear: Bool
    let shape: NotchShape

    var body: some View {
        Color.clear.glassEffect(clear ? .clear : .regular, in: shape)
    }
}
#endif

/// Solid black where the camera is, fading into the glass below.
/// Without it, a glass island looks like it's sticking out of the top of the screen.
private struct NotchCap: View {
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let total = max(1, proxy.size.height)
            let solid = min(1, height / total)
            let faded = min(1, (height + 28) / total)
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: solid),
                    .init(color: .black.opacity(0), location: max(solid, faded)),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }
}

/// The classic macOS blur behind a window.
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

/// True when this Mac shows real Liquid Glass.
var hasLiquidGlass: Bool {
    #if compiler(>=6.2)
    if #available(macOS 26.0, *) { return true }
    #endif
    return false
}
