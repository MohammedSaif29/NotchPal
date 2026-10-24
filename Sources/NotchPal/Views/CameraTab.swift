// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// Mirror: a quick look at yourself before a call, with macOS's video effects one click away.
/// The camera turns off as soon as you leave this tab.
struct CameraTab: View {
    let app: AppModel

    var body: some View {
        let camera = app.camera
        Group {
            switch camera.status {
            case .denied:
                CameraMessage(app: app, symbol: "video.slash.fill",
                              text: "Camera access is off. Turn on NotchPal in Privacy & Security → Camera. If it's already on, switch it off and on again.",
                              button: "Open Settings") {
                    camera.openPrivacySettings()
                }
            case .unavailable:
                CameraMessage(app: app, symbol: "video.slash.fill", text: "No camera found.", button: nil) {}
            case .failed(let message):
                CameraMessage(app: app, symbol: "exclamationmark.triangle.fill", text: message, button: "Try Again") {
                    camera.restart()
                }
            case .idle, .starting, .running:
                MirrorView(app: app)
            }
        }
        .onAppear { camera.start(mirrored: app.settings.mirrorFlip) }
        .onDisappear { camera.stop() }
        .onChange(of: app.settings.mirrorFlip) {
            camera.setMirrored(app.settings.mirrorFlip)
        }
    }
}

/// Where the picture goes: a circle, or a rectangle with the camera's own proportions,
/// so your head is never squashed or cut off. It sits right under the camera.
private struct MirrorFrame {
    static let gap: CGFloat = 12
    /// The narrowest the side panels get.
    static let minSide: CGFloat = 76
    /// Side panels at least this wide show names next to their icons.
    static let roomySide: CGFloat = 118

    var size: CGSize
    var side: CGFloat

    static func make(in space: CGSize, shape: MirrorShape, aspect: CGFloat) -> MirrorFrame {
        let maxWidth = max(60, space.width - 2 * (minSide + gap))
        let width: CGFloat
        let height: CGFloat
        switch shape {
        case .circle:
            width = min(space.height, maxWidth)
            height = width
        case .rectangle:
            width = min(space.height * aspect, maxWidth)
            height = width / aspect
        }
        let side = max(0, (space.width - width) / 2 - gap)
        return MirrorFrame(size: CGSize(width: width, height: height), side: side)
    }
}

/// Effects on the left, your picture in the middle, and the controls on the right.
private struct MirrorView: View {
    let app: AppModel

    var body: some View {
        let camera = app.camera
        GeometryReader { proxy in
            let frame = MirrorFrame.make(in: proxy.size, shape: app.settings.mirrorShape, aspect: camera.aspectRatio)
            HStack(spacing: MirrorFrame.gap) {
                EffectsPanel(app: app, roomy: frame.side >= MirrorFrame.roomySide)
                    .frame(width: frame.side)
                mirror(camera)
                    .frame(width: frame.size.width, height: frame.size.height)
                MirrorControls(app: app, roomy: frame.side >= MirrorFrame.roomySide)
                    .frame(width: frame.side)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func mirror(_ camera: CameraService) -> some View {
        let circle = app.settings.mirrorShape == .circle
        let radius: CGFloat = 20
        return CameraPreview(previewLayer: camera.previewLayer, cornerRadius: radius,
                             aspectRatio: camera.aspectRatio, circle: circle)
            .overlay {
                // A soft glassy rim that follows the picture's shape, even mid-morph.
                MirrorOutline(radius: radius, aspectRatio: camera.aspectRatio, circle: circle)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            }
            .overlay {
                if camera.status != .running {
                    VStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Starting…")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
    }
}

// MARK: Effects

/// The video effects the Mirror offers. Centre Stage and Reactions work right here.
/// Portrait, Studio Light and Background are switched in macOS's own Video Effects panel,
/// because macOS only lets you (not apps) turn those on and off.
private enum MirrorEffect: String, Identifiable {
    case centerStage
    case portrait
    case studioLight
    case background
    case reactions
    case deskView

    var id: Self { self }

    var title: String {
        switch self {
        case .centerStage: "Centre Stage"
        case .portrait: "Portrait"
        case .studioLight: "Studio Light"
        case .background: "Background"
        case .reactions: "Reactions"
        case .deskView: "Desk View"
        }
    }

    var symbol: String {
        switch self {
        case .centerStage: "person.fill.viewfinder"
        case .portrait: "f.cursive"
        case .studioLight: "cube"
        case .background: "person.and.background.dotted"
        case .reactions: "hand.thumbsup.fill"
        case .deskView: "doc.viewfinder"
        }
    }

    func isOn(_ effects: CameraEffects) -> Bool {
        switch self {
        case .centerStage: effects.centerStage.on
        case .portrait: effects.portrait.on
        case .studioLight: effects.studioLight.on
        case .background: effects.background.on
        case .reactions: effects.reactions.on
        case .deskView: false
        }
    }

    func help(on: Bool, canReact: Bool) -> String {
        switch self {
        case .centerStage:
            on ? "Centre Stage is on: the camera keeps you in frame as you move. Click to turn it off."
                : "Turn on Centre Stage to keep you in frame as you move"
        case .portrait, .studioLight, .background:
            "\(title) is \(on ? "on" : "off"). Click to change it in Video Effects."
        case .reactions:
            canReact ? "Play a reaction on your picture" : "Turn on Reactions in Video Effects to play them here"
        case .deskView:
            "Open Desk View to show your desk from above"
        }
    }

    /// The effects this camera can do, in the same order as macOS's panel.
    @MainActor
    static func available(_ effects: CameraEffects) -> [MirrorEffect] {
        var list: [MirrorEffect] = []
        if effects.centerStage.supported { list.append(.centerStage) }
        if effects.portrait.supported { list.append(.portrait) }
        if effects.studioLight.supported { list.append(.studioLight) }
        if effects.reactions.supported { list.append(.reactions) }
        if effects.background.supported { list.append(.background) }
        if !list.isEmpty && DeskView.appURL != nil { list.append(.deskView) }
        return list
    }
}

private struct EffectsPanel: View {
    let app: AppModel
    let roomy: Bool

    var body: some View {
        let effects = MirrorEffect.available(app.camera.effects)
        if effects.isEmpty {
            MirrorInfo(app: app)
        } else if roomy {
            VStack(alignment: .leading, spacing: 5) {
                CameraHeader(app: app)
                    .padding(.bottom, 1)
                ForEach(effects) { effect in
                    EffectButton(app: app, effect: effect, showsTitle: true)
                }
                Spacer(minLength: 4)
                NeverRecordedLabel()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.vertical, 2)
        } else {
            LazyVGrid(columns: [GridItem(.fixed(28), spacing: 8), GridItem(.fixed(28))], alignment: .leading, spacing: 8) {
                ForEach(effects) { effect in
                    EffectButton(app: app, effect: effect, showsTitle: false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.vertical, 2)
        }
    }
}

private struct EffectButton: View {
    let app: AppModel
    let effect: MirrorEffect
    let showsTitle: Bool

    private static let green = Color(red: 0.19, green: 0.78, blue: 0.35)

    var body: some View {
        let camera = app.camera
        let on = effect.isOn(camera.effects)
        Button(action: perform) {
            HStack(spacing: 8) {
                Image(systemName: effect.symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(on ? Color.white : Color.white.opacity(0.8))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(on ? Self.green : Color.white.opacity(0.12)))
                if showsTitle {
                    Text(effect.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(on ? 0.95 : 0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .help(effect.help(on: on, canReact: !camera.reactionChoices.isEmpty))
    }

    private func perform() {
        let camera = app.camera
        switch effect {
        case .centerStage:
            camera.setCenterStage(!camera.effects.centerStage.on)
        case .reactions where !camera.reactionChoices.isEmpty:
            IslandMenu.popUp(camera.reactionChoices.map { choice in
                IslandMenu.Item(title: choice.title, symbol: choice.symbol) {
                    camera.react(choice.id)
                }
            }, header: "Play a reaction")
        case .deskView:
            app.closeIsland()
            DeskView.open()
        default:
            app.openVideoEffects()
        }
    }
}

/// The camera's name. With more than one camera (an iPhone, say), it's a menu to switch.
private struct CameraHeader: View {
    let app: AppModel

    var body: some View {
        let camera = app.camera
        let name = camera.cameraName.isEmpty ? "Camera" : camera.cameraName
        if camera.cameras.count > 1 {
            Button {
                IslandMenu.popUp(camera.cameras.map { choice in
                    IslandMenu.Item(title: choice.name, checked: choice.id == camera.cameraID) {
                        camera.selectCamera(choice)
                    }
                }, header: "Camera")
            } label: {
                HStack(spacing: 4) {
                    Text(name)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .help("Choose a camera")
        } else {
            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// Shown when the camera has no video effects, or before they've loaded.
private struct MirrorInfo: View {
    let app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Mirror")
                .font(.system(size: 14, weight: .semibold))
            CameraHeader(app: app)
            Spacer(minLength: 6)
            NeverRecordedLabel()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.vertical, 4)
    }
}

private struct NeverRecordedLabel: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.green)
                .frame(width: 5, height: 5)
            Text("Never recorded")
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.white.opacity(0.45))
    }
}

// MARK: Controls

private struct MirrorControls: View {
    let app: AppModel
    let roomy: Bool

    var body: some View {
        let panelOpen = app.state.effectsPanelOpen
        VStack(alignment: .trailing, spacing: 8) {
            MirrorButton(symbol: "xmark", help: "Turn off the camera and close") {
                app.camera.stop()
                app.closeIsland()
            }
            Spacer(minLength: 6)
            if app.camera.status == .running {
                VideoEffectsButton(open: panelOpen, showsTitle: roomy) {
                    if panelOpen {
                        app.state.effectsPanelOpenedAt = nil
                    } else {
                        app.openVideoEffects()
                    }
                }
            }
            if roomy {
                HStack(spacing: 8) {
                    shapeSwitch
                    flipButton
                }
            } else {
                shapeSwitch
                flipButton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.vertical, 2)
    }

    private var shapeSwitch: some View {
        ShapeSwitch(shape: app.settings.mirrorShape) { shape in
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                app.settings.mirrorShape = shape
            }
        }
    }

    private var flipButton: some View {
        MirrorButton(symbol: "arrow.left.and.right", help: "Flip the picture") {
            app.settings.mirrorFlip = !app.settings.mirrorFlip
        }
    }
}

/// Opens macOS's Video Effects panel, with Portrait, Studio Light, Edge Light, Background and more.
/// While it's open, this becomes a Done button.
private struct VideoEffectsButton: View {
    let open: Bool
    let showsTitle: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: open ? "checkmark" : "camera.filters")
                    .font(.system(size: 11, weight: .bold))
                if showsTitle {
                    Text(open ? "Done" : "Video Effects")
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, showsTitle ? 11 : 0)
            .frame(width: showsTitle ? nil : 28, height: 28)
            .foregroundStyle(open ? Color.black : Color.white)
            .background(Capsule().fill(open ? Color.white : Color.white.opacity(0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .help(open ? "Done with Video Effects" : "All video effects: Portrait, Studio Light, Edge Light, Background and more")
    }
}

/// Round or rectangle.
private struct ShapeSwitch: View {
    let shape: MirrorShape
    let choose: (MirrorShape) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MirrorShape.allCases) { option in
                Button { choose(option) } label: {
                    Image(systemName: option.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 24)
                        .background(Capsule().fill(Color.white.opacity(option == shape ? 0.22 : 0)))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .opacity(option == shape ? 1 : 0.6)
                .help(option.label)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }
}

private struct MirrorButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .help(help)
    }
}

private struct CameraMessage: View {
    let app: AppModel
    let symbol: String
    let text: String
    let button: String?
    let action: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
            ViewThatFits(in: .vertical) {
                content(showIcon: true)
                content(showIcon: false)
            }
        }
        .overlay(alignment: .topTrailing) {
            MirrorButton(symbol: "xmark", help: "Close") {
                app.camera.stop()
                app.closeIsland()
            }
            .padding(8)
        }
    }

    private func content(showIcon: Bool) -> some View {
        VStack(spacing: 8) {
            if showIcon {
                Image(systemName: symbol)
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            if let button {
                Button(action: action) {
                    Text(button)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(Capsule().fill(Color.white.opacity(0.16)))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
            }
        }
    }
}
