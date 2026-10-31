// Core/SystemControls.swift
// The system knobs the trackpad edge controls turn:
//   • VolumeControl     — CoreAudio virtual main volume + mute on the default output device
//   • BrightnessControl — built-in display brightness via the private DisplayServices framework
//   • MediaKeys         — synthesized media keys (play/pause, next, previous, volume/brightness)
//   • SystemOSD         — the native volume/brightness bezel, via the OSDUIHelper XPC service
//
// Every control degrades gracefully: if a direct API is unavailable (e.g. an HDMI output
// without a software volume, or no built-in display) callers fall back to media keys,
// which macOS handles itself (and draws its own OSD for).

import AppKit
import CoreAudio
import CoreGraphics
import Foundation

// MARK: - VolumeControl

enum VolumeControl {

    /// 'vmvc' — kAudioHardwareServiceDeviceProperty_VirtualMainVolume (AudioToolbox).
    /// Spelled out so we only need CoreAudio.
    private static let virtualMainVolume: AudioObjectPropertySelector = 0x766D_7663

    private static func defaultOutputDevice() -> AudioObjectID? {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    /// Current volume 0…1, or nil when the output device has no software volume.
    static func get() -> Float? {
        guard let device = defaultOutputDevice() else { return nil }
        var addr = address(virtualMainVolume)
        guard AudioObjectHasProperty(device, &addr) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    /// Sets the volume 0…1. Returns false if the device does not allow it.
    @discardableResult
    static func set(_ newValue: Float) -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        var addr = address(virtualMainVolume)
        guard AudioObjectHasProperty(device, &addr) else { return false }
        var value = Float32(min(max(newValue, 0), 1))
        let size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectSetPropertyData(device, &addr, 0, nil, size, &value) == noErr else { return false }
        // Raising the volume from a muted state should be audible, like the keyboard keys.
        if value > 0, isMuted() == true { setMuted(false) }
        return true
    }

    static func isMuted() -> Bool? {
        guard let device = defaultOutputDevice() else { return nil }
        var addr = address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(device, &addr) else { return nil }
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &muted) == noErr else { return nil }
        return muted != 0
    }

    @discardableResult
    static func setMuted(_ muted: Bool) -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        var addr = address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(device, &addr) else { return false }
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(device, &addr, 0, nil, size, &value) == noErr
    }
}

// MARK: - BrightnessControl

enum BrightnessControl {

    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let functions: (get: GetFn, set: SetFn)? = {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_NOW),
              let getPtr = dlsym(handle, "DisplayServicesGetBrightness"),
              let setPtr = dlsym(handle, "DisplayServicesSetBrightness") else {
            Log.info("BrightnessControl: DisplayServices unavailable — falling back to brightness keys.")
            return nil
        }
        return (unsafeBitCast(getPtr, to: GetFn.self), unsafeBitCast(setPtr, to: SetFn.self))
    }()

    /// The built-in panel if one is online, otherwise the main display.
    static var targetDisplay: CGDirectDisplayID {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return ids.first(where: { CGDisplayIsBuiltin($0) != 0 }) ?? CGMainDisplayID()
    }

    static func get() -> Float? {
        guard let fns = functions else { return nil }
        var value: Float = 0
        guard fns.get(targetDisplay, &value) == 0 else { return nil }
        return value
    }

    @discardableResult
    static func set(_ newValue: Float) -> Bool {
        guard let fns = functions else { return false }
        return fns.set(targetDisplay, min(max(newValue, 0), 1)) == 0
    }
}

// MARK: - MediaKeys

enum MediaKey: Int {
    // NX_KEYTYPE_* values from IOKit/hidsystem/ev_keymap.h
    case soundUp = 0
    case soundDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
    case illuminationUp = 21
    case illuminationDown = 22
    case play = 16
    case next = 17
    case previous = 18
}

enum MediaKeys {
    /// Posts a key-down + key-up pair for a media key. Must run on the main thread.
    static func post(_ key: MediaKey) {
        func send(down: Bool) {
            let state = down ? 0xA : 0xB
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,                       // NX_SUBTYPE_AUX_CONTROL_BUTTONS
                data1: (key.rawValue << 16) | (state << 8),
                data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
        send(down: true)
        send(down: false)
    }
}

// MARK: - SystemOSD

/// The XPC interface exported by /System/Library/CoreServices/OSDUIHelper.app.
/// Signature confirmed from the binary's type encoding: v48@0:8q16I24I28I32I36I40B44.
@objc protocol OSDUIHelperProtocol {
    @objc(showImage:onDisplayID:priority:msecUntilFade:filledChiclets:totalChiclets:locked:)
    func showImage(_ image: Int64, onDisplayID displayID: UInt32, priority: UInt32,
                   msecUntilFade: UInt32, filledChiclets: UInt32, totalChiclets: UInt32,
                   locked: Bool)
}

final class SystemOSD {

    enum Image: Int64 {
        case brightness = 1
        case volume = 3
        case muted = 4
    }

    static let shared = SystemOSD()

    private var connection: NSXPCConnection?

    private init() {}

    /// Shows the native bezel. `level` is 0…1; it is drawn as `chiclets` segments.
    /// Main thread only.
    func show(_ image: Image, level: Float, chiclets: UInt32 = 16) {
        let filled = UInt32((min(max(level, 0), 1) * Float(chiclets)).rounded())
        let proxy = activeConnection().remoteObjectProxyWithErrorHandler { [weak self] error in
            Log.info("SystemOSD: XPC error: \(error)")
            DispatchQueue.main.async { self?.connection = nil }
        } as? OSDUIHelperProtocol
        proxy?.showImage(image.rawValue,
                         onDisplayID: CGMainDisplayID(),
                         priority: 0x1F4,
                         msecUntilFade: 1000,
                         filledChiclets: filled,
                         totalChiclets: chiclets,
                         locked: false)
    }

    private func activeConnection() -> NSXPCConnection {
        if let existing = connection { return existing }
        let conn = NSXPCConnection(machServiceName: "com.apple.OSDUIHelper", options: [])
        conn.remoteObjectInterface = NSXPCInterface(with: OSDUIHelperProtocol.self)
        conn.invalidationHandler = { [weak self] in
            DispatchQueue.main.async { self?.connection = nil }
        }
        conn.resume()
        connection = conn
        return conn
    }
}
