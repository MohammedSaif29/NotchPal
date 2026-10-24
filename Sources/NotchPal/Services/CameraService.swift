// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
@preconcurrency import AVFoundation
import CoreMedia
import Observation
import SwiftUI

/// A camera you can pick in the Mirror, like the Mac's own camera or an iPhone.
struct CameraChoice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

/// macOS's video effects for the camera in use, as the Video Effects panel shows them.
struct CameraEffects: Equatable, Sendable {
    struct Effect: Equatable, Sendable {
        /// The camera can do it.
        var supported = false
        /// It's turned on.
        var on = false
    }

    var centerStage = Effect()
    var portrait = Effect()
    var studioLight = Effect()
    var background = Effect()
    /// `on` means Reactions are turned on in Video Effects.
    var reactions = Effect()
    /// The reactions that can play right now. Empty while Reactions are off.
    var reactionTypes: [String] = []
}

/// A reaction you can play in the Mirror: hearts, balloons, confetti…
struct ReactionChoice: Identifiable, Sendable {
    let id: String
    let title: String
    let symbol: String
}

enum MirrorReactions {
    static let all: [ReactionChoice] = [
        ReactionChoice(id: AVCaptureReactionType.thumbsUp.rawValue, title: "Thumbs Up", symbol: "hand.thumbsup.fill"),
        ReactionChoice(id: AVCaptureReactionType.thumbsDown.rawValue, title: "Thumbs Down", symbol: "hand.thumbsdown.fill"),
        ReactionChoice(id: AVCaptureReactionType.heart.rawValue, title: "Hearts", symbol: "heart.fill"),
        ReactionChoice(id: AVCaptureReactionType.balloons.rawValue, title: "Balloons", symbol: "balloon.2.fill"),
        ReactionChoice(id: AVCaptureReactionType.confetti.rawValue, title: "Confetti", symbol: "party.popper.fill"),
        ReactionChoice(id: AVCaptureReactionType.fireworks.rawValue, title: "Fireworks", symbol: "fireworks"),
        ReactionChoice(id: AVCaptureReactionType.rain.rawValue, title: "Rain", symbol: "cloud.rain.fill"),
        ReactionChoice(id: AVCaptureReactionType.lasers.rawValue, title: "Lasers", symbol: "sparkles"),
    ]
}

/// The camera mirror. It only runs while the Mirror tab is open, and nothing is ever recorded.
///
/// All the slow camera work (finding the camera, starting, stopping, mirroring, effects) happens
/// on `CameraWorker`'s own queue. The main thread never waits on the camera, so the island stays
/// responsive even while the camera is warming up.
@MainActor
@Observable
final class CameraService {
    enum Status: Equatable {
        case idle
        case starting
        case running
        case denied
        case unavailable
        case failed(String)
    }

    private(set) var status: Status = .idle
    /// Name of the camera in use, e.g. "MacBook Air Camera".
    private(set) var cameraName = ""
    private(set) var cameraID = ""
    /// Every camera you could switch to.
    private(set) var cameras: [CameraChoice] = []
    /// The camera picture's width divided by its height. 16:9 on Mac cameras.
    private(set) var aspectRatio: CGFloat = 16.0 / 9.0
    /// Kept after the camera turns off, so the Mirror looks the same next time.
    private(set) var effects = CameraEffects()

    let session = AVCaptureSession()
    /// One preview layer for the app's whole life. It's connected to the session once, while the
    /// camera is off, and the Mirror tab just shows it.
    let previewLayer = AVCaptureVideoPreviewLayer()

    private let worker = CameraWorker()
    @ObservationIgnored private var wanted = false
    @ObservationIgnored private var mirrored = true
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var effectsTimer: Timer?
    @ObservationIgnored private var polls = 0

    private static let preferredCameraKey = "mirrorCamera"

    init() {
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.backgroundColor = NSColor.black.cgColor
    }

    /// The reactions you can play right now, in a nice order.
    var reactionChoices: [ReactionChoice] {
        let available = Set(effects.reactionTypes)
        return MirrorReactions.all.filter { available.contains($0.id) }
    }

    func start(mirrored: Bool) {
        wanted = true
        self.mirrored = mirrored
        watchForErrors()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            status = .starting
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if !granted {
                            self.status = .denied
                        } else if self.wanted {
                            self.run()
                        }
                    }
                }
            }
        default:
            status = .denied
        }
    }

    func stop() {
        wanted = false
        effectsTimer?.invalidate()
        effectsTimer = nil
        worker.stop(session)
        if status == .running || status == .starting {
            status = .idle
        }
    }

    /// Try again after an error.
    func restart() {
        let mirror = mirrored
        stop()
        worker.reset(session)
        start(mirrored: mirror)
    }

    func setMirrored(_ mirrored: Bool) {
        guard mirrored != self.mirrored else { return }
        self.mirrored = mirrored
        worker.applyMirror(mirrored, to: session)
    }

    /// Switch to another camera. NotchPal remembers it for next time.
    func selectCamera(_ choice: CameraChoice) {
        guard choice.id != cameraID, wanted else { return }
        UserDefaults.standard.set(choice.id, forKey: Self.preferredCameraKey)
        status = .starting
        worker.switchCamera(to: choice.id, session: session, mirrored: mirrored) { [weak self] outcome in
            self?.finish(outcome)
        }
    }

    /// Centre Stage keeps you in the middle of the picture as you move.
    func setCenterStage(_ on: Bool) {
        var updated = effects
        updated.centerStage.on = on
        effects = updated // Show it straight away; the camera confirms a moment later.
        worker.setCenterStage(on) { [weak self] in
            self?.readEffects()
        }
    }

    /// Plays a reaction, like balloons, on your picture.
    func react(_ type: String) {
        worker.react(type, in: session)
    }

    /// macOS's own Video Effects panel, where Portrait, Studio Light, Background and the rest are switched.
    func showVideoEffects() {
        AVCaptureDevice.showSystemUserInterface(.videoEffects)
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    private func run() {
        status = .starting
        let preferred = UserDefaults.standard.string(forKey: Self.preferredCameraKey)
        worker.start(session, mirrored: mirrored, preferredID: preferred) { [weak self] outcome in
            self?.finish(outcome)
        }
    }

    private func finish(_ outcome: CameraWorker.Outcome) {
        switch outcome {
        case .running(let name, let aspect, let id):
            guard wanted else {
                stop()
                return
            }
            if cameraName != name { cameraName = name }
            if cameraID != id { cameraID = id }
            if abs(aspectRatio - aspect) > 0.01 { aspectRatio = aspect }
            status = .running
            watchEffects()
            refreshCameras()
        case .noCamera:
            status = .unavailable
        case .failed(let message):
            status = .failed(message)
        }
    }

    /// The effects can change any time in the Video Effects panel, so check every second while the camera is on.
    private func watchEffects() {
        effectsTimer?.invalidate()
        readEffects()
        let tick = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollEffects() }
        }
        RunLoop.main.add(tick, forMode: .common)
        effectsTimer = tick
    }

    private func pollEffects() {
        guard status == .running else { return }
        readEffects()
        polls += 1
        if polls % 5 == 0 {
            refreshCameras()
        }
    }

    private func readEffects() {
        worker.readEffects(session) { [weak self] effects in
            guard let self, self.effects != effects else { return }
            self.effects = effects
        }
    }

    private func refreshCameras() {
        worker.listCameras { [weak self] cameras in
            guard let self, self.cameras != cameras else { return }
            self.cameras = cameras
        }
    }

    private func watchForErrors() {
        guard observers.isEmpty else { return }
        observers.append(NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main
        ) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
            let message = error?.localizedDescription ?? "The camera stopped unexpectedly."
            MainActor.assumeIsolated {
                guard let self, self.wanted else { return }
                self.status = .failed(message)
            }
        })
    }
}

/// Does every camera call on its own serial queue.
final class CameraWorker: @unchecked Sendable {
    enum Outcome {
        /// The camera's name, its picture's width divided by height, and its ID.
        case running(String, CGFloat, String)
        case noCamera
        case failed(String)
    }

    private let queue = DispatchQueue(label: "notchpal.camera", qos: .userInitiated)
    /// Only touched on `queue`.
    private var configured = false

    func start(_ session: AVCaptureSession, mirrored: Bool, preferredID: String?,
               completion: @escaping @MainActor (Outcome) -> Void) {
        queue.async {
            let outcome = self.configureAndRun(session, mirrored: mirrored, preferredID: preferredID)
            Self.deliver(outcome, to: completion)
        }
    }

    func switchCamera(to id: String, session: AVCaptureSession, mirrored: Bool,
                      completion: @escaping @MainActor (Outcome) -> Void) {
        queue.async {
            self.removeInputs(session)
            let outcome = self.configureAndRun(session, mirrored: mirrored, preferredID: id)
            Self.deliver(outcome, to: completion)
        }
    }

    func stop(_ session: AVCaptureSession) {
        queue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    func reset(_ session: AVCaptureSession) {
        queue.async {
            self.removeInputs(session)
        }
    }

    func applyMirror(_ mirrored: Bool, to session: AVCaptureSession) {
        queue.async {
            Self.mirror(session, mirrored)
        }
    }

    func readEffects(_ session: AVCaptureSession, completion: @escaping @MainActor (CameraEffects) -> Void) {
        queue.async {
            let effects = Self.effects(of: Self.device(in: session))
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(effects) }
            }
        }
    }

    func listCameras(completion: @escaping @MainActor ([CameraChoice]) -> Void) {
        queue.async {
            let cameras = Self.discover().map { CameraChoice(id: $0.uniqueID, name: $0.localizedName) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(cameras) }
            }
        }
    }

    func setCenterStage(_ on: Bool, completion: @escaping @MainActor () -> Void) {
        queue.async {
            // Apps may only switch Centre Stage when they share control of it with you.
            if AVCaptureDevice.centerStageControlMode != .cooperative {
                AVCaptureDevice.centerStageControlMode = .cooperative
            }
            AVCaptureDevice.isCenterStageEnabled = on
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion() }
            }
        }
    }

    func react(_ type: String, in session: AVCaptureSession) {
        queue.async {
            guard let device = Self.device(in: session), device.canPerformReactionEffects else { return }
            let reaction = AVCaptureReactionType(rawValue: type)
            guard device.availableReactionTypes.contains(reaction) else { return }
            device.performEffect(for: reaction)
        }
    }

    private static func deliver(_ outcome: Outcome, to completion: @escaping @MainActor (Outcome) -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { completion(outcome) }
        }
    }

    private func removeInputs(_ session: AVCaptureSession) {
        configured = false
        session.beginConfiguration()
        for input in session.inputs {
            session.removeInput(input)
        }
        session.commitConfiguration()
    }

    private func configureAndRun(_ session: AVCaptureSession, mirrored: Bool, preferredID: String?) -> Outcome {
        if !configured {
            guard let device = Self.pickCamera(preferredID: preferredID) else { return .noCamera }
            let input: AVCaptureDeviceInput
            do {
                input = try AVCaptureDeviceInput(device: device)
            } catch {
                return .failed(error.localizedDescription)
            }
            session.beginConfiguration()
            if session.canSetSessionPreset(.high) {
                session.sessionPreset = .high
            }
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                return .failed("The camera is busy in another app.")
            }
            session.addInput(input)
            session.commitConfiguration()
            configured = true
        }
        Self.mirror(session, mirrored)
        if !session.isRunning {
            session.startRunning()
        }
        guard session.isRunning, let device = Self.device(in: session) else {
            return .failed("The camera didn't start. It might be in use by another app.")
        }
        var aspect: CGFloat = 16.0 / 9.0
        let size = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        if size.width > 0 && size.height > 0 {
            aspect = CGFloat(size.width) / CGFloat(size.height)
        }
        return .running(device.localizedName, aspect, device.uniqueID)
    }

    private static func device(in session: AVCaptureSession) -> AVCaptureDevice? {
        (session.inputs.first as? AVCaptureDeviceInput)?.device
    }

    private static func effects(of device: AVCaptureDevice?) -> CameraEffects {
        var effects = CameraEffects()
        guard let device else { return effects }
        let format = device.activeFormat
        effects.centerStage = .init(supported: format.isCenterStageSupported, on: AVCaptureDevice.isCenterStageEnabled)
        effects.portrait = .init(supported: format.isPortraitEffectSupported, on: AVCaptureDevice.isPortraitEffectEnabled)
        effects.studioLight = .init(supported: format.isStudioLightSupported, on: AVCaptureDevice.isStudioLightEnabled)
        if #available(macOS 15.0, *) {
            effects.background = .init(supported: format.isBackgroundReplacementSupported,
                                       on: AVCaptureDevice.isBackgroundReplacementEnabled)
        }
        effects.reactions = .init(supported: format.reactionEffectsSupported, on: AVCaptureDevice.reactionEffectsEnabled)
        if device.canPerformReactionEffects {
            effects.reactionTypes = device.availableReactionTypes.map(\.rawValue).sorted()
        }
        return effects
    }

    private static func mirror(_ session: AVCaptureSession, _ mirrored: Bool) {
        for connection in session.connections where connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
    }

    /// The Mac's camera, an iPhone, other cameras, and Desk View when the Mac offers it.
    private static func discover() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external, .deskViewCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    /// The camera you picked last time, otherwise the Mac's own camera, then any other camera.
    private static func pickCamera(preferredID: String?) -> AVCaptureDevice? {
        if let preferredID, let device = AVCaptureDevice(uniqueID: preferredID) {
            return device
        }
        let devices = discover().filter { $0.deviceType != .deskViewCamera }
        return devices.first { $0.deviceType == .builtInWideAngleCamera }
            ?? devices.first
            ?? AVCaptureDevice.default(for: .video)
    }
}

/// macOS's Desk View app, which shows your desk from above using the camera.
@MainActor
enum DeskView {
    static let appURL: URL? = {
        for id in ["com.apple.DeskView", "com.apple.deskview"] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                return url
            }
        }
        for path in ["/System/Library/CoreServices/Desk View.app", "/System/Applications/Desk View.app"]
            where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }()

    static func open() {
        guard let appURL else { return }
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Finds macOS's Video Effects panel on screen. Control Center shows it, and its menu bar
/// items are small, so a new big Control Center window is the panel.
enum VideoEffectsPanel {
    @MainActor
    static var controlCenterPID: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first?.processIdentifier
    }

    /// Control Center's big windows on screen right now. Safe to call from any thread.
    static func largeWindows(of pid: pid_t?) -> Set<Int> {
        guard let pid,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        var found: Set<Int> = []
        for window in list {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  let number = (window[kCGWindowNumber as String] as? NSNumber)?.intValue,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width > 120, rect.height > 120
            else { continue }
            found.insert(number)
        }
        return found
    }
}

/// The mirror's corners at any size. A square is a circle, the camera's own proportions get
/// the normal corner radius, and sizes in between blend, so switching shape morphs smoothly.
/// The picture and the rim around it both use this, so they always match.
enum MirrorCorners {
    static func shape(for size: CGSize, radius: CGFloat, aspectRatio: CGFloat, circle: Bool) -> (radius: CGFloat, circular: Bool) {
        guard size.width > 0, size.height > 0 else { return (0, false) }
        let roundest = min(size.width, size.height) / 2
        var roundness: CGFloat = circle ? 1 : 0
        if aspectRatio > 1.05 {
            let shape = max(size.width, size.height) / min(size.width, size.height)
            roundness = min(1, max(0, (aspectRatio - shape) / (aspectRatio - 1)))
        }
        return (min(roundest, radius + (roundest - radius) * roundness), roundness > 0.98)
    }
}

/// The outline of the mirror, for drawing a rim that follows the picture exactly.
struct MirrorOutline: InsettableShape {
    var radius: CGFloat
    var aspectRatio: CGFloat
    var circle: Bool
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let corners = MirrorCorners.shape(for: rect.size, radius: radius, aspectRatio: aspectRatio, circle: circle)
        let inner = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard inner.width > 0, inner.height > 0 else { return Path() }
        return Path(roundedRect: inner, cornerRadius: max(0, corners.radius - insetAmount),
                    style: corners.circular ? .circular : .continuous)
    }

    func inset(by amount: CGFloat) -> MirrorOutline {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

/// Shows the camera's shared preview layer. Showing or hiding it never touches the camera itself.
struct CameraPreview: NSViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer
    /// Corner radius when the view has the camera's own proportions.
    var cornerRadius: CGFloat = 18
    /// The camera's width divided by height.
    var aspectRatio: CGFloat = 16.0 / 9.0
    var circle = false

    func makeNSView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.show(previewLayer)
        view.setCorners(radius: cornerRadius, aspectRatio: aspectRatio, circle: circle)
        return view
    }

    func updateNSView(_ nsView: CameraPreviewView, context: Context) {
        nsView.setCorners(radius: cornerRadius, aspectRatio: aspectRatio, circle: circle)
    }

    static func dismantleNSView(_ nsView: CameraPreviewView, coordinator: ()) {
        nsView.hide()
    }
}

/// A layer-hosting view that holds the preview layer and keeps it filling the view.
final class CameraPreviewView: NSView {
    private weak var preview: CALayer?
    private var radius: CGFloat = 18
    private var aspectRatio: CGFloat = 16.0 / 9.0
    private var circle = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let host = CALayer()
        host.backgroundColor = NSColor.black.cgColor
        host.masksToBounds = true
        // Setting the layer before wantsLayer makes this a layer-hosting view,
        // so AppKit leaves our sublayer alone.
        layer = host
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func show(_ previewLayer: CALayer) {
        previewLayer.removeFromSuperlayer()
        layer?.addSublayer(previewLayer)
        preview = previewLayer
        fit()
    }

    func hide() {
        // A newer preview may have taken the layer already. Only remove it from this view.
        if let preview, preview.superlayer === layer {
            preview.removeFromSuperlayer()
        }
        preview = nil
    }

    func setCorners(radius: CGFloat, aspectRatio: CGFloat, circle: Bool) {
        self.radius = radius
        self.aspectRatio = aspectRatio
        self.circle = circle
        fit()
    }

    override func layout() {
        super.layout()
        fit()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        fit()
    }

    private func fit() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview?.frame = bounds
        if let layer {
            let corners = MirrorCorners.shape(for: bounds.size, radius: radius, aspectRatio: aspectRatio, circle: circle)
            layer.cornerCurve = corners.circular ? .circular : .continuous
            layer.cornerRadius = corners.radius
        }
        CATransaction.commit()
    }
}
