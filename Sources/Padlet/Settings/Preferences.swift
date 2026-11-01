// Settings/Preferences.swift
// Everything the user can change, persisted as JSON blobs in UserDefaults and published
// so the panel, the quick menu and GestureCoordinator stay in sync.
//
// All decoders read key by key with defaults, so adding a setting never resets the rest.

import Combine
import Foundation

// MARK: - Decoding helper

private extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}

// MARK: - FeatureFlags

struct FeatureFlags: Codable, Equatable {
    /// Master switch. Off = the multitouch listener is stopped completely.
    var masterEnabled = true
    var threeFinger = true
    var fourFinger = true
    var cornerForceClick = true
    var edgeControls = true
    var topEdge = true
    var appProfiles = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FeatureFlags()
        masterEnabled    = c.value(.masterEnabled, d.masterEnabled)
        threeFinger      = c.value(.threeFinger, d.threeFinger)
        fourFinger       = c.value(.fourFinger, d.fourFinger)
        cornerForceClick = c.value(.cornerForceClick, d.cornerForceClick)
        edgeControls     = c.value(.edgeControls, d.edgeControls)
        topEdge          = c.value(.topEdge, d.topEdge)
        appProfiles      = c.value(.appProfiles, d.appProfiles)
    }

    func isEnabled(_ family: GestureFamily) -> Bool {
        switch family {
        case .threeFinger: return threeFinger
        case .fourFinger: return fourFinger
        case .cornerForceClick: return cornerForceClick
        case .topEdge: return topEdge
        }
    }
}

// MARK: - EdgeFunction

/// What sliding along a side edge controls.
enum EdgeFunction: String, Codable, CaseIterable, Identifiable {
    case off, volume, brightness, keyboardBacklight, scroll, zoom

    enum Kind { case none, level, steps, continuous }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .volume: return "Volume"
        case .brightness: return "Brightness"
        case .keyboardBacklight: return "Keyboard Light"
        case .scroll: return "Scroll"
        case .zoom: return "Zoom"
        }
    }

    var symbol: String {
        switch self {
        case .off: return "nosign"
        case .volume: return "speaker.wave.2.fill"
        case .brightness: return "sun.max.fill"
        case .keyboardBacklight: return "light.max"
        case .scroll: return "arrow.up.and.down"
        case .zoom: return "plus.magnifyingglass"
        }
    }

    /// level = absolute 0…1 value with OSD; steps = discrete key presses;
    /// continuous = streamed deltas (scroll).
    var kind: Kind {
        switch self {
        case .off: return .none
        case .volume, .brightness: return .level
        case .keyboardBacklight, .zoom: return .steps
        case .scroll: return .continuous
        }
    }
}

// MARK: - EdgeSettings

struct EdgeSettings: Codable, Equatable {
    var leftFunction: EdgeFunction = .brightness
    var rightFunction: EdgeFunction = .volume
    /// Width of the side strips, as a fraction of trackpad width.
    var edgeWidth: Double = 0.06
    /// How much of the full range one full trackpad height covers.
    var sensitivity: Double = 1.5
    var bottomQuarterOnly = false
    /// Only slide while Fn or Option is held.
    var requireModifier = false
    var freezeCursor = true
    /// Always use quarter steps (otherwise hold ⇧⌥).
    var fineControlAlways = false
    /// Double-tap the top-right corner to mute / unmute.
    var quickMute = true
    /// Swipe along the bottom edge to skip tracks.
    var mediaStrip = true
    /// Double-tap the bottom edge to play / pause.
    var mediaTap = false
    var invertMediaSwipe = false
    /// Ignore new edge touches this long after a key press.
    var typingGuardMs: Double = 300

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        let d = EdgeSettings()
        // v1 stored a single "swapSides" flag instead of per-side functions.
        let legacySwap: Bool = c.value(AnyKey("swapSides"), false)
        leftFunction      = c.value(AnyKey("leftFunction"), legacySwap ? .volume : d.leftFunction)
        rightFunction     = c.value(AnyKey("rightFunction"), legacySwap ? .brightness : d.rightFunction)
        edgeWidth         = c.value(AnyKey("edgeWidth"), d.edgeWidth)
        sensitivity       = c.value(AnyKey("sensitivity"), d.sensitivity)
        bottomQuarterOnly = c.value(AnyKey("bottomQuarterOnly"), d.bottomQuarterOnly)
        requireModifier   = c.value(AnyKey("requireModifier"), d.requireModifier)
        freezeCursor      = c.value(AnyKey("freezeCursor"), d.freezeCursor)
        fineControlAlways = c.value(AnyKey("fineControlAlways"), d.fineControlAlways)
        quickMute         = c.value(AnyKey("quickMute"), d.quickMute)
        mediaStrip        = c.value(AnyKey("mediaStrip"), d.mediaStrip)
        mediaTap          = c.value(AnyKey("mediaTap"), d.mediaTap)
        invertMediaSwipe  = c.value(AnyKey("invertMediaSwipe"), d.invertMediaSwipe)
        typingGuardMs     = c.value(AnyKey("typingGuardMs"), d.typingGuardMs)
    }

    func function(forLeftEdge left: Bool) -> EdgeFunction {
        left ? leftFunction : rightFunction
    }
}

struct AnyKey: CodingKey {
    let stringValue: String
    init(_ s: String) { stringValue = s }
    init(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { nil }
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
    var onboardingCompleted = false
    /// Open at Login is turned on once, on the first launch; afterwards the user's choice wins.
    var openAtLoginDefaultApplied = false
    /// System-wide shortcut that turns every gesture on/off. None by default.
    var toggleHotKey: KeyCombo?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GeneralSettings()
        hapticStrength            = c.value(.hapticStrength, d.hapticStrength)
        appearance                = c.value(.appearance, d.appearance)
        autoCheckUpdates          = c.value(.autoCheckUpdates, d.autoCheckUpdates)
        autoInstallUpdates        = c.value(.autoInstallUpdates, d.autoInstallUpdates)
        onboardingCompleted       = c.value(.onboardingCompleted, d.onboardingCompleted)
        openAtLoginDefaultApplied = c.value(.openAtLoginDefaultApplied, d.openAtLoginDefaultApplied)
        toggleHotKey              = c.value(.toggleHotKey, d.toggleHotKey)
    }
}

// MARK: - AppProfile

/// Per-app overrides: while `bundleID` is frontmost, these slots use these actions.
struct AppProfile: Codable, Equatable, Identifiable {
    var id = UUID()
    var bundleID: String
    var name: String
    var enabled = true
    /// GestureSlot raw value → action. A missing slot uses the global mapping.
    var overrides: [String: GestureAction] = [:]

    subscript(slot: GestureSlot) -> GestureAction? {
        get { overrides[slot.rawValue] }
        set { overrides[slot.rawValue] = newValue }
    }
}

// MARK: - Preferences store

final class Preferences: ObservableObject {

    static let shared = Preferences()

    private enum Key {
        static let flags = "featureFlags"
        static let edge = "edgeSettings"
        static let general = "generalSettings"
        static let profiles = "appProfiles"
    }

    @Published var flags: FeatureFlags {
        didSet { if flags != oldValue { save(flags, Key.flags) } }
    }
    @Published var edge: EdgeSettings {
        didSet { if edge != oldValue { save(edge, Key.edge) } }
    }
    @Published var general: GeneralSettings {
        didSet { if general != oldValue { save(general, Key.general) } }
    }
    @Published var mapping: GestureMapping {
        didSet { if mapping != oldValue { mapping.save(to: defaults) } }
    }
    @Published var profiles: [AppProfile] {
        didSet { if profiles != oldValue { save(profiles, Key.profiles) } }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        LegacyMigration.run(into: defaults)
        flags = Self.load(FeatureFlags.self, Key.flags, defaults) ?? FeatureFlags()
        edge = Self.load(EdgeSettings.self, Key.edge, defaults) ?? EdgeSettings()
        general = Self.load(GeneralSettings.self, Key.general, defaults) ?? GeneralSettings()
        mapping = GestureMapping.load(from: defaults)
        profiles = Self.load([AppProfile].self, Key.profiles, defaults) ?? []
    }

    /// The action for `slot` while `bundleID` is frontmost (profile override first).
    func action(for slot: GestureSlot, frontmostBundleID bundleID: String?) -> GestureAction {
        if flags.appProfiles, let bundleID = bundleID,
           let profile = profiles.first(where: { $0.enabled && $0.bundleID == bundleID }),
           let override = profile[slot] {
            return override
        }
        return mapping[slot]
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String, _ defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}

// MARK: - Migration from "Mac Shortcuts" (com.mac-shortcuts.app)

enum LegacyMigration {
    static let legacyDomain = "com.mac-shortcuts.app"
    private static let doneKey = "migratedFromMacShortcuts"
    private static let keys = ["gestureMapping", "featureFlags", "edgeSettings", "generalSettings"]

    static func run(into defaults: UserDefaults) {
        guard defaults === UserDefaults.standard,
              Bundle.main.bundleIdentifier != legacyDomain,
              !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }
        guard let legacy = UserDefaults(suiteName: legacyDomain) else { return }
        var copied: [String] = []
        for key in keys where defaults.object(forKey: key) == nil {
            if let value = legacy.object(forKey: key) {
                defaults.set(value, forKey: key)
                copied.append(key)
            }
        }
        if !copied.isEmpty { Log.info("Migrated settings from Mac Shortcuts: \(copied.joined(separator: ", "))") }
    }
}
