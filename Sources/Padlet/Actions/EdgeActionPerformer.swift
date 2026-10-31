// Actions/EdgeActionPerformer.swift
// Turns EdgeEvents into system changes. Main thread.
//
//   level functions (volume, brightness) — absolute value 0…1, quantized to 16 steps
//       (64 in fine mode), native OSD, haptic tick per step. Falls back to media keys
//       when the direct API is unavailable (e.g. an external display).
//   step functions (keyboard light, zoom) — one key press per step of travel.
//   continuous (scroll)                  — scroll-wheel events streamed with the finger.

import AppKit
import CoreGraphics
import Foundation

extension Notification.Name {
    /// Posted on every applied edge step. userInfo: "function" (EdgeFunction), "value" (Float?).
    static let padletEdgeActivity = Notification.Name("Padlet.edgeActivity")
}

final class EdgeActionPerformer {

    /// Runs a mapped gesture (top-edge swipes resolve through mapping + app profiles).
    var performGesture: ((GestureSlot) -> Void)?

    private struct Slide {
        let function: EdgeFunction
        var value: Float = 0            // level: current 0…1
        var lastApplied: Float = 0      // level: last quantized value sent
        var accumulator: Float = 0      // steps / key fallback: travel since last step
        var useKeys = false
    }

    private var slide: Slide?
    private var deviceID: UInt64?

    func handle(_ event: EdgeEvent, device: TouchDevice?) {
        deviceID = device?.deviceID

        switch event {
        case .slideBegan(let function, let anchor):
            begin(function)
            if let anchor = anchor { CursorFreezer.shared.freeze(at: anchor) }

        case .slid(let function, let delta, let fine):
            if slide == nil { begin(function) }
            apply(delta: delta, fine: fine)

        case .slideEnded:
            slide = nil
            CursorFreezer.shared.release()

        case .mediaSwipe(let forward, let restore):
            MediaKeys.post(forward ? .next : .previous)
            if let p = restore { CGWarpMouseCursorPosition(p) }
            tick()

        case .topSwipe(let slot, let restore):
            performGesture?(slot)
            if let p = restore { CGWarpMouseCursorPosition(p) }
            tick()

        case .doubleTap(.muteCorner):
            toggleMute()
            tick()

        case .doubleTap(.mediaStrip):
            MediaKeys.post(.play)
            tick()

        case .armClickSuppressor:
            ClickSuppressor.shared.arm(for: 0.5)
        }
    }

    /// Releases anything held (engine stopped mid-slide).
    func reset() {
        slide = nil
        CursorFreezer.shared.release()
    }

    // MARK: - Slides

    private func begin(_ function: EdgeFunction) {
        var s = Slide(function: function)
        if function.kind == .level {
            if let v = read(function) {
                s.value = v
                s.lastApplied = (v * 16).rounded() / 16
            } else {
                s.useKeys = true
            }
        }
        slide = s
    }

    private func apply(delta: Float, fine: Bool) {
        guard var s = slide else { return }
        defer { slide = s }

        switch s.function.kind {
        case .none:
            return

        case .level where !s.useKeys:
            let steps: Float = fine ? 64 : 16
            s.value = min(max(s.value + delta, 0), 1)
            let q = (s.value * steps).rounded() / steps
            guard q != s.lastApplied else { return }
            s.lastApplied = q
            write(s.function, q, chiclets: UInt32(steps))
            tick()
            announce(s.function, q)

        case .level, .steps:
            let stepSize: Float = s.function == .zoom ? 0.1 : (fine ? 1.0 / 64 : 1.0 / 16)
            s.accumulator += delta
            while abs(s.accumulator) >= stepSize {
                let up = s.accumulator > 0
                s.accumulator -= up ? stepSize : -stepSize
                stepKey(s.function, up: up)
                tick()
            }
            announce(s.function, nil)

        case .continuous:
            scroll(delta)
        }
    }

    private func read(_ function: EdgeFunction) -> Float? {
        switch function {
        case .volume: return VolumeControl.get()
        case .brightness: return BrightnessControl.get()
        default: return nil
        }
    }

    private func write(_ function: EdgeFunction, _ value: Float, chiclets: UInt32) {
        switch function {
        case .volume:
            if VolumeControl.set(value) {
                SystemOSD.shared.show(value == 0 ? .muted : .volume, level: value, chiclets: chiclets)
            }
        case .brightness:
            if BrightnessControl.set(value) {
                SystemOSD.shared.show(.brightness, level: value, chiclets: chiclets)
            }
        default:
            break
        }
    }

    private func stepKey(_ function: EdgeFunction, up: Bool) {
        switch function {
        case .volume: MediaKeys.post(up ? .soundUp : .soundDown)
        case .brightness: MediaKeys.post(up ? .brightnessUp : .brightnessDown)
        case .keyboardBacklight: MediaKeys.post(up ? .illuminationUp : .illuminationDown)
        case .zoom: ActionExecutor.shared.postKey(up ? 24 : 27, flags: .maskCommand)   // ⌘= / ⌘-
        default: break
        }
    }

    private func scroll(_ delta: Float) {
        // Follow the system's scroll direction ("natural" by default on trackpads).
        let natural = UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool ?? true
        let pixels = Int32((delta * 1600).rounded()) * (natural ? -1 : 1)
        guard pixels != 0 else { return }
        CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                wheel1: pixels, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
    }

    private func toggleMute() {
        if let muted = VolumeControl.isMuted(), VolumeControl.setMuted(!muted) {
            let level = VolumeControl.get() ?? 0
            SystemOSD.shared.show(muted ? .volume : .muted, level: muted ? level : 0)
        } else {
            MediaKeys.post(.mute)
        }
    }

    private func tick() {
        TrackpadHaptics.shared.tick(deviceID: deviceID)
    }

    private func announce(_ function: EdgeFunction, _ value: Float?) {
        var info: [String: Any] = ["function": function]
        if let value = value { info["value"] = value }
        NotificationCenter.default.post(name: .padletEdgeActivity, object: nil, userInfo: info)
    }
}
