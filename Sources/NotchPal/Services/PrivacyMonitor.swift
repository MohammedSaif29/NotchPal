// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import CoreAudio
import Foundation
import CoreMediaIO
import Observation

/// Notices when any app is using the camera or microphone, so the notch can show
/// the iPhone-style green and orange dots. Only checks "in use", never sees or hears anything,
/// and needs no permissions.
@MainActor
@Observable
final class PrivacyMonitor {
    private(set) var cameraInUse = false
    private(set) var micInUse = false

    var inUse: Bool { cameraInUse || micInUse }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var checking = false
    /// The checks talk to the camera and audio systems, which can be slow while a camera
    /// starts up, so they run here instead of on the main thread.
    private let queue = DispatchQueue(label: "notchpal.privacy", qos: .utility)

    func start() {
        guard timer == nil else { return }
        let tick = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
        poll()
    }

    private func poll() {
        guard !checking else { return } // The last check is still running.
        checking = true
        queue.async { [weak self] in
            let camera = PrivacyProbe.anyCameraRunning()
            let mic = PrivacyProbe.microphoneRunning()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.checking = false
                    if camera != self.cameraInUse { self.cameraInUse = camera }
                    if mic != self.micInUse { self.micInUse = mic }
                }
            }
        }
    }
}

private enum PrivacyProbe {
    static func anyCameraRunning() -> Bool {
        var devicesAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &devicesAddress, 0, nil, &size) == 0, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &devicesAddress, 0, nil, size, &used, &devices) == 0 else { return false }

        for device in devices {
            var runningAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            var running: UInt32 = 0
            var runningUsed: UInt32 = 0
            let status = CMIOObjectGetPropertyData(device, &runningAddress, 0, nil,
                                                   UInt32(MemoryLayout<UInt32>.size), &runningUsed, &running)
            if status == 0 && running != 0 {
                return true
            }
        }
        return false
    }

    static func microphoneRunning() -> Bool {
        var inputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &inputAddress, 0, nil, &size, &device) == noErr,
              device != 0
        else { return false }

        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var runningSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &runningAddress, 0, nil, &runningSize, &running) == noErr else { return false }
        return running != 0
    }
}
