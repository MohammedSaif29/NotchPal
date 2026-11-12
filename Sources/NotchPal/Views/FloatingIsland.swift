// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

/// The floating island's surface: black, or the same glass as the notch, with rounded corners.
struct CardBackground: View {
    let look: IslandLook
    var cornerRadius: CGFloat = 28

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            switch look.style {
            case .black:
                shape.fill(Color.black)
            case .glass, .frosted, .clear:
                glassBase(shape)
                if let tint = look.tint {
                    shape.fill(tint.opacity(look.style == .clear ? 0.12 : 0.2))
                }
                shape.fill(Color.black.opacity(look.darkness))
                if look.readabilityShade > 0 {
                    EllipticalGradient(
                        colors: [Color.black.opacity(look.readabilityShade), Color.black.opacity(look.readabilityShade * 0.35)],
                        center: .center, startRadiusFraction: 0.15, endRadiusFraction: 0.8
                    )
                    .clipShape(shape)
                }
                if look.border {
                    shape.strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.4), Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func glassBase(_ shape: RoundedRectangle) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), look.style != .frosted {
            Color.clear.glassEffect(look.style == .clear ? .clear : .regular, in: shape)
        } else {
            VisualEffectBlur(material: look.style == .clear ? .fullScreenUI : .hudWindow).clipShape(shape)
        }
        #else
        VisualEffectBlur(material: look.style == .clear ? .fullScreenUI : .hudWindow).clipShape(shape)
        #endif
    }
}

/// The open island splitting off the notch and floating down below it like a droplet, then
/// melting back up into the notch when it closes. A stretchy black neck joins them on the way.
struct CardSplit: ViewModifier, Animatable {
    /// 0 tucked inside the notch, 1 floating in place.
    var progress: Double
    let islandWidth: CGFloat
    let islandHeight: CGFloat
    let topRadius: CGFloat
    let bottomRadius: CGFloat
    let cardSize: CGSize
    /// Draw the stretchy neck: only when the notch and the card are both black.
    let neck: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let p = CGFloat(min(1, max(0, progress)))
        let finalTop = islandHeight + IslandLayout.cardGap
        let startTop = max(0, islandHeight - 18)
        let top = startTop + (finalTop - startTop) * p
        let scaleX = 0.2 + 0.8 * p
        let scaleY = 0.1 + 0.9 * p
        let canvasWidth = max(cardSize.width, islandWidth) + 80
        let canvasHeight = finalTop + cardSize.height + 40

        ZStack(alignment: .top) {
            if neck && progress > 0.02 && progress < 0.97 {
                Canvas { graphics, size in
                    let center = size.width / 2
                    let island = CGRect(x: center - islandWidth / 2, y: 0, width: islandWidth, height: islandHeight)
                    graphics.clip(to: NotchShape(topRadius: topRadius, bottomRadius: bottomRadius).path(in: island),
                                  options: .inverse)
                    graphics.addFilter(.alphaThreshold(min: 0.5, color: .black))
                    graphics.addFilter(.blur(radius: 13 * (1 - p) + 1))
                    graphics.drawLayer { layer in
                        let neckWidth = min(islandWidth * 0.55, max(40, cardSize.width * scaleX * 0.6))
                        layer.fill(Path(roundedRect: CGRect(x: center - neckWidth / 2, y: islandHeight - 34,
                                                            width: neckWidth, height: 34), cornerRadius: 16),
                                   with: .color(.black))
                        let width = cardSize.width * scaleX
                        let height = cardSize.height * scaleY
                        layer.fill(Path(roundedRect: CGRect(x: center - width / 2, y: top, width: width, height: height),
                                        cornerRadius: min(28, height / 2)),
                                   with: .color(.black))
                    }
                }
                .frame(width: canvasWidth, height: canvasHeight)
                .allowsHitTesting(false)
            }
            content
                .scaleEffect(x: scaleX, y: scaleY, anchor: .top)
                .opacity(min(1, Double(p) * 1.8))
                .offset(y: top)
        }
        .frame(width: canvasWidth, height: canvasHeight, alignment: .top)
    }
}

/// Apple's "black hole": when the pointer comes up under the notch, a drop of the notch
/// stretches down toward it, as if the pointer is being pulled in.
struct PointerMagnet: View {
    let state: IslandState
    let islandWidth: CGFloat
    let islandHeight: CGFloat
    let topRadius: CGFloat
    let bottomRadius: CGFloat

    /// How far below the notch the pull reaches.
    static let reach: CGFloat = 46

    var body: some View {
        let pointer = state.pointer
        Canvas { graphics, size in
            guard let pointer else { return }
            let center = size.width / 2
            let below = pointer.y - islandHeight
            guard below > -2, below < Self.reach, abs(pointer.x) < islandWidth / 2 + 30 else { return }
            let pull = 1 - max(0, below) / Self.reach
            let island = CGRect(x: center - islandWidth / 2, y: 0, width: islandWidth, height: islandHeight)
            graphics.clip(to: NotchShape(topRadius: topRadius, bottomRadius: bottomRadius).path(in: island),
                          options: .inverse)
            graphics.addFilter(.alphaThreshold(min: 0.5, color: .black))
            graphics.addFilter(.blur(radius: 7))
            graphics.drawLayer { layer in
                layer.fill(NotchShape(topRadius: topRadius, bottomRadius: bottomRadius).path(in: island), with: .color(.black))
                // The drop trails behind the pointer a little, and grows the closer it gets.
                let x = center + min(islandWidth / 2 - 10, max(-islandWidth / 2 + 10, pointer.x))
                let y = islandHeight + max(0, below) * 0.55
                let radius = 4 + 9 * pull
                layer.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                           with: .color(.black))
            }
        }
        .frame(width: islandWidth + 120, height: islandHeight + Self.reach + 20)
        .allowsHitTesting(false)
    }
}
