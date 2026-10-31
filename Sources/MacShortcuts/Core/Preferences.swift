// Core/Preferences.swift
// User-facing switches that sit above the gesture→action mapping:
//   • FeatureFlags — the master on/off switch plus one switch per gesture family
//     (three-finger tap/click, corner force click, edge controls).
//   • EdgeSettings — tuning for the trackpad edge controls (volume / brightness strips,
//     quick mute corner, media strip). Modeled on EdgeBar's settings menu.
//
// Both are persisted as JSON in UserDefaults and published so the menu bar, the
// Settings window and GestureCoordinator all stay in sync.

import Combine
import Foundation

// MARK: - FeatureFlags

struct FeatureFlags: Codable, Equatable {
    /// Master switch. When false the multitouch listener is stopped completely.
    var masterEnabled = true
    /// Three Finger Tap + Three Finger Click.
    var threeFinger = true
    /// Force click in the four trackpad corners.
    var cornerForceClick = true
    /// Volume / brightness edges, quick mute corner and media strip.
    var edgeControls = true

    init() {}

    // Decode key by key so adding a flag later never wipes the user's other choices.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FeatureFlags()
        masterEnabled    = try c.decodeIfPresent(Bool.self, forKey: .masterEnabled) ?? d.masterEnabled
        threeFinger      = try c.decodeIfPresent(Bool.self, forKey: .threeFinger) ?? d.threeFinger
        cornerForceClick = try c.decodeIfPresent(Bool.self, forKey: .cornerForceClick) ?? d.cornerForceClick
        edgeControls     = try c.decodeIfPresent(Bool.self, forKey: .edgeControls) ?? d.edgeControls
    }
}

// MARK: - EdgeSettings

struct EdgeSettings: Codable, Equatable {
    /// false: left edge = brightness, right edge = volume. true: swapped.
    var swapSides = false
    /// Width of the left/right edge strips, as a fraction of trackpad width.
    var edgeWidth: Double = 0.06
    /// How much of the full 0–100% range one full trackpad height covers.
    var sensitivity: Double = 1.5
    /// Only start edge slides in the lower 25% of the trackpad.
    var bottomQuarterOnly = false
    /// Only slide while Fn or Option is held.
    var requireModifier = false
    /// Pin the pointer in place while sliding on an edge.
    var freezeCursor = true
    /// Always use quarter steps (otherwise hold Shift+Option).
    var fineControlAlways = false
    /// Light haptic tick on every step.
    var haptics = true
    /// Double-tap the top-right corner to mute / unmute.
    var quickMute = true
    /// Swipe along the bottom edge to skip tracks.
    var mediaStrip = true
    /// Double-tap the bottom edge to play / pause.
    var mediaTap = false
    /// Reverse the direction of the media swipe.
    var invertMediaSwipe = false
    /// Ignore new edge touches for this many ms after a key press (palm while typing).
    var typingGuardMs: Double = 300

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = EdgeSettings()
        swapSides         = try c.decodeIfPresent(Bool.self, forKey: .swapSides) ?? d.swapSides
        edgeWidth         = try c.decodeIfPresent(Double.self, forKey: .edgeWidth) ?? d.edgeWidth
        sensitivity       = try c.decodeIfPresent(Double.self, forKey: .sensitivity) ?? d.sensitivity
        bottomQuarterOnly = try c.decodeIfPresent(Bool.self, forKey: .bottomQuarterOnly) ?? d.bottomQuarterOnly
        requireModifier   = try c.decodeIfPresent(Bool.self, forKey: .requireModifier) ?? d.requireModifier
        freezeCursor      = try c.decodeIfPresent(Bool.self, forKey: .freezeCursor) ?? d.freezeCursor
        fineControlAlways = try c.decodeIfPresent(Bool.self, forKey: .fineControlAlways) ?? d.fineControlAlways
        haptics           = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? d.haptics
        quickMute         = try c.decodeIfPresent(Bool.self, forKey: .quickMute) ?? d.quickMute
        mediaStrip        = try c.decodeIfPresent(Bool.self, forKey: .mediaStrip) ?? d.mediaStrip
        mediaTap          = try c.decodeIfPresent(Bool.self, forKey: .mediaTap) ?? d.mediaTap
        invertMediaSwipe  = try c.decodeIfPresent(Bool.self, forKey: .invertMediaSwipe) ?? d.invertMediaSwipe
        typingGuardMs     = try c.decodeIfPresent(Double.self, forKey: .typingGuardMs) ?? d.typingGuardMs
    }
}

// MARK: - GeneralSettings

enum HapticStrength: Int, Codable, CaseIterable, Identifiable {
    case off = 0, light, medium, strong
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .off: return "Off"
        case .light: return "Light"
        case .medium: return "Medium"
        case .strong: return "Strong"
        }
    }
}

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct GeneralSettings: Codable, Equatable {
    var hapticStrength: HapticStrength = .medium
    var appearance: AppearanceMode = .system
    var autoCheckUpdates = true
    var autoInstallUpdates = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GeneralSettings()
        hapticStrength     = (try? c.decodeIfPresent(HapticStrength.self, forKey: .hapticStrength)) ?? d.hapticStrength
        appearance         = (try? c.decodeIfPresent(AppearanceMode.self, forKey: .appearance)) ?? d.appearance
        autoCheckUpdates   = try c.decodeIfPresent(Bool.self, forKey: .autoCheckUpdates) ?? d.autoCheckUpdates
        autoInstallUpdates = try c.decodeIfPresent(Bool.self, forKey: .autoInstallUpdates) ?? d.autoInstallUpdates
    }
}

// MARK: - Preferences store

final class Preferences: ObservableObject {

    static let shared = Preferences()

    private static let flagsKey = "featureFlags"
    private static let edgeKey = "edgeSettings"
    private static let generalKey = "generalSettings"

    @Published var general: GeneralSettings {
        didSet { if general != oldValue { Self.save(general, key: Self.generalKey) } }
    }

    /// Gesture → action table. Persisted by GestureMapping itself (its existing storage key).
    @Published var mapping: GestureMapping = GestureMapping.load() {
        didSet { if mapping != oldValue { mapping.save() } }
    }

    @Published var flags: FeatureFlags {
        didSet { if flags != oldValue { Self.save(flags, key: Self.flagsKey) } }
    }

    @Published var edge: EdgeSettings {
        didSet { if edge != oldValue { Self.save(edge, key: Self.edgeKey) } }
    }

    private init() {
        flags = Self.load(FeatureFlags.self, key: Self.flagsKey) ?? FeatureFlags()
        edge = Self.load(EdgeSettings.self, key: Self.edgeKey) ?? EdgeSettings()
        general = Self.load(GeneralSettings.self, key: Self.generalKey) ?? GeneralSettings()
    }

    // MARK: Persistence

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
