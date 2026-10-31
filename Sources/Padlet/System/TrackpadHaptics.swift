// System/TrackpadHaptics.swift
// Haptic ticks with a real strength setting.
//
// NSHapticFeedbackManager offers three patterns that all feel about the same. The trackpad's
// Force Touch actuator (MultitouchSupport's MTActuator* API) takes an actuation ID whose
// waveforms differ noticeably in strength, so we drive it directly on the trackpad the
// finger is on, and fall back to NSHapticFeedbackManager when that isn't possible.
//
// Main thread only.

import AppKit
import Foundation

final class TrackpadHaptics {

    static let shared = TrackpadHaptics()

    private var actuators: [UInt64: CFTypeRef] = [:]
    private var unavailable: Set<UInt64> = []

    private init() {}

    /// Actuation waveform per strength (higher = stronger).
    static func actuationID(for strength: HapticStrength) -> Int32 {
        switch strength {
        case .off: return 0
        case .light: return 3
        case .medium: return 4
        case .strong: return 6
        }
    }

    func tick(_ strength: HapticStrength = Preferences.shared.general.hapticStrength, deviceID: UInt64?) {
        guard strength != .off else { return }

        let fw = MultitouchFramework.shared
        if let id = deviceID, id != 0, let actuate = fw.MTActuatorActuate, let actuator = actuator(for: id) {
            if actuate(actuator, Self.actuationID(for: strength), 0, 0, 0) == 0 { return }
            // The actuator went away (sleep, unplug) — drop it and fall back this time.
            close(id)
        }

        let pattern: NSHapticFeedbackManager.FeedbackPattern
        switch strength {
        case .off: return
        case .light: pattern = .alignment
        case .medium: pattern = .levelChange
        case .strong: pattern = .generic
        }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    /// Close every actuator (sleep / engine stop). They are reopened on demand.
    func reset() {
        for id in Array(actuators.keys) { close(id) }
        unavailable.removeAll()
    }

    private func actuator(for deviceID: UInt64) -> CFTypeRef? {
        if let existing = actuators[deviceID] { return existing }
        guard !unavailable.contains(deviceID) else { return nil }
        let fw = MultitouchFramework.shared
        guard let create = fw.MTActuatorCreateFromDeviceID, let open = fw.MTActuatorOpen,
              let actuator = create(deviceID)?.takeRetainedValue(),
              open(actuator) == 0 else {
            unavailable.insert(deviceID)
            Log.info("TrackpadHaptics: no actuator for device \(deviceID); using NSHapticFeedbackManager.")
            return nil
        }
        actuators[deviceID] = actuator
        return actuator
    }

    private func close(_ deviceID: UInt64) {
        if let actuator = actuators.removeValue(forKey: deviceID) {
            _ = MultitouchFramework.shared.MTActuatorClose?(actuator)
        }
    }
}
