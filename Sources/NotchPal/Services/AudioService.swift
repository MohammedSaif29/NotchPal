// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AudioToolbox
import CoreAudio
import Observation
import SwiftUI

/// A speaker, headphones, or display the Mac can play sound through.
struct AudioOutput: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let transport: UInt32

    var isWireless: Bool {
        transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    var symbol: String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpodsmax" }
        if lower.contains("airpods pro") { return "airpodspro" }
        if lower.contains("airpods") { return "airpods" }
        if lower.contains("beats") { return "beats.headphones" }
        switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return "headphones"
        case kAudioDeviceTransportTypeBuiltIn:
            return "laptopcomputer"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return "tv"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        default:
            return "hifispeaker"
        }
    }
}

/// System volume and the output device (speakers, AirPods…), through Core Audio.
/// No permissions needed.
@MainActor
@Observable
final class AudioService {
    private(set) var outputs: [AudioOutput] = []
    private(set) var current: AudioOutput?
    private(set) var volume: Double = 0.5
    private(set) var isMuted = false

    /// Called when the Mac switches to a new wireless output, e.g. AirPods connecting.
    @ObservationIgnored var onWirelessConnect: (@MainActor (AudioOutput) -> Void)?

    @ObservationIgnored private var started = false
    @ObservationIgnored private var watchedDevice: AudioDeviceID = 0
    @ObservationIgnored private var volumeListener: AudioObjectPropertyListenerBlock?

    func start() {
        guard !started else { return }
        started = true

        let system = AudioObjectID(kAudioObjectSystemObject)
        var devices = CoreAudioBits.address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(system, &devices, DispatchQueue.main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.reload(announce: false) }
        }
        var defaultOutput = CoreAudioBits.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(system, &defaultOutput, DispatchQueue.main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.reload(announce: true) }
        }
        reload(announce: false)
    }

    func setVolume(_ value: Double) {
        guard let device = current?.id else { return }
        let clamped = min(1, max(0, value))
        volume = clamped
        if isMuted && clamped > 0 {
            CoreAudioBits.setMuted(false, device: device)
            isMuted = false
        }
        CoreAudioBits.setVolume(clamped, device: device)
    }

    func toggleMute() {
        guard let device = current?.id else { return }
        let muted = !isMuted
        CoreAudioBits.setMuted(muted, device: device)
        isMuted = muted
    }

    func select(_ output: AudioOutput) {
        CoreAudioBits.setDefaultOutput(output.id)
    }

    private func reload(announce: Bool) {
        let previous = current
        outputs = CoreAudioBits.outputDevices()
        let id = CoreAudioBits.defaultOutputDevice()
        current = outputs.first { $0.id == id }
        watchVolume(of: id)
        readVolume()
        if announce, let current, current.id != previous?.id,
           current.isWireless || current.name.lowercased().contains("airpods") {
            onWirelessConnect?(current)
        }
    }

    private func readVolume() {
        guard let device = current?.id else { return }
        if let value = CoreAudioBits.volume(of: device), abs(value - volume) > 0.001 {
            volume = value
        }
        let muted = CoreAudioBits.isMuted(device)
        if muted != isMuted {
            isMuted = muted
        }
    }

    /// Follows volume changes made with the keyboard or Control Center.
    private func watchVolume(of device: AudioDeviceID) {
        guard device != watchedDevice else { return }
        if watchedDevice != 0, let listener = volumeListener {
            var volumeAddress = CoreAudioBits.address(CoreAudioBits.virtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
            AudioObjectRemovePropertyListenerBlock(watchedDevice, &volumeAddress, DispatchQueue.main, listener)
            var muteAddress = CoreAudioBits.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
            AudioObjectRemovePropertyListenerBlock(watchedDevice, &muteAddress, DispatchQueue.main, listener)
        }
        watchedDevice = device
        volumeListener = nil
        guard device != 0 else { return }

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.readVolume() }
        }
        volumeListener = listener
        var volumeAddress = CoreAudioBits.address(CoreAudioBits.virtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        AudioObjectAddPropertyListenerBlock(device, &volumeAddress, DispatchQueue.main, listener)
        var muteAddress = CoreAudioBits.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        AudioObjectAddPropertyListenerBlock(device, &muteAddress, DispatchQueue.main, listener)
    }
}

/// Thin wrappers around the Core Audio C functions.
private enum CoreAudioBits {
    /// 'vmvc': the device's main volume, the same one the volume keys change.
    static let virtualMainVolume: AudioObjectPropertySelector = 0x766D_7663

    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func defaultOutputDevice() -> AudioDeviceID {
        var property = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, &device)
        return status == noErr ? device : 0
    }

    static func setDefaultOutput(_ device: AudioDeviceID) {
        var property = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var value = device
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil,
                                   UInt32(MemoryLayout<AudioDeviceID>.size), &value)
    }

    static func outputDevices() -> [AudioOutput] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var property = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &property, 0, nil, &size) == noErr, size > 0 else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &property, 0, nil, &size, &devices) == noErr else { return [] }
        return devices.compactMap { device in
            guard hasOutput(device) else { return nil }
            return AudioOutput(id: device, name: name(of: device), transport: transport(of: device))
        }
    }

    static func hasOutput(_ device: AudioDeviceID) -> Bool {
        var property = Self.address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &property, 0, nil, &size) == noErr && size > 0
    }

    static func name(of device: AudioDeviceID) -> String {
        var property = Self.address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &name) == noErr, let name else {
            return "Unknown device"
        }
        return name.takeRetainedValue() as String
    }

    static func transport(of device: AudioDeviceID) -> UInt32 {
        var property = Self.address(kAudioDevicePropertyTransportType)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }

    static func volume(of device: AudioDeviceID) -> Double? {
        var property = Self.address(virtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr else { return nil }
        return Double(value)
    }

    static func setVolume(_ volume: Double, device: AudioDeviceID) {
        var property = Self.address(virtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        var value = Float32(volume)
        AudioObjectSetPropertyData(device, &property, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    static func isMuted(_ device: AudioDeviceID) -> Bool {
        var property = Self.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    static func setMuted(_ muted: Bool, device: AudioDeviceID) {
        var property = Self.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(device, &property, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }
}
