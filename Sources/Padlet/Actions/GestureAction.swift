// Actions/GestureAction.swift
// Everything a mapped gesture can do. Persisted as {"type": "...", ...} JSON; a built-in
// action's type is its BuiltinAction raw value, so v1/v2.0 settings still decode.

import AppKit
import Foundation

/// Actions that need no extra input. Raw values are persisted — never rename one.
enum BuiltinAction: String, CaseIterable, Codable {
    // Mouse
    case middleClick
    // System
    case missionControl, appExpose, showDesktop, spotlight, screenshot, lockScreen
    // Spaces
    case previousSpace, nextSpace
    // Windows
    case moveToNextDisplay, moveToPreviousDisplay
    case maximizeWindow, leftHalf, rightHalf, centerWindow
    case minimizeWindow, toggleFullScreen, closeWindow
    // Tabs & navigation
    case previousTab, nextTab, newTab, closeTab, reopenTab, back, forward
    // Apps
    case previousApp, quitApp
    // Media
    case playPause, nextTrack, previousTrack, mute

    enum Group: String, CaseIterable {
        case mouse = "Mouse", system = "System", spaces = "Spaces", windows = "Windows"
        case tabs = "Tabs & Navigation", apps = "Apps", media = "Media"
    }

    var group: Group {
        switch self {
        case .middleClick: return .mouse
        case .missionControl, .appExpose, .showDesktop, .spotlight, .screenshot, .lockScreen: return .system
        case .previousSpace, .nextSpace: return .spaces
        case .moveToNextDisplay, .moveToPreviousDisplay, .maximizeWindow, .leftHalf, .rightHalf,
             .centerWindow, .minimizeWindow, .toggleFullScreen, .closeWindow: return .windows
        case .previousTab, .nextTab, .newTab, .closeTab, .reopenTab, .back, .forward: return .tabs
        case .previousApp, .quitApp: return .apps
        case .playPause, .nextTrack, .previousTrack, .mute: return .media
        }
    }

    var title: String {
        switch self {
        case .middleClick: return "Middle Click"
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé"
        case .showDesktop: return "Show Desktop"
        case .spotlight: return "Spotlight"
        case .screenshot: return "Screenshot"
        case .lockScreen: return "Lock Screen"
        case .previousSpace: return "Previous Space"
        case .nextSpace: return "Next Space"
        case .moveToNextDisplay: return "Move Window to Next Display"
        case .moveToPreviousDisplay: return "Move Window to Previous Display"
        case .maximizeWindow: return "Fill Screen"
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .centerWindow: return "Center Window"
        case .minimizeWindow: return "Minimize Window"
        case .toggleFullScreen: return "Toggle Full Screen"
        case .closeWindow: return "Close Window"
        case .previousTab: return "Previous Tab"
        case .nextTab: return "Next Tab"
        case .newTab: return "New Tab"
        case .closeTab: return "Close Tab"
        case .reopenTab: return "Reopen Closed Tab"
        case .back: return "Back"
        case .forward: return "Forward"
        case .previousApp: return "Switch to Previous App"
        case .quitApp: return "Quit App"
        case .playPause: return "Play / Pause"
        case .nextTrack: return "Next Track"
        case .previousTrack: return "Previous Track"
        case .mute: return "Mute / Unmute"
        }
    }

    static func cases(in group: Group) -> [BuiltinAction] { allCases.filter { $0.group == group } }
}

enum GestureAction: Codable, Equatable, Hashable {
    case none
    case builtin(BuiltinAction)
    /// `key` is a character ("w") or a named key ("←", "F5", "Space" — see KeyCodes).
    case keystroke(key: String, modifiers: NSEvent.ModifierFlags)
    case openApp(bundleID: String)
    /// Runs a shortcut from the Shortcuts app by name.
    case runShortcut(name: String)

    // Shorthands, so call sites read like the old flat enum.
    static var middleClick: GestureAction { .builtin(.middleClick) }
    static var missionControl: GestureAction { .builtin(.missionControl) }
    static var appExpose: GestureAction { .builtin(.appExpose) }
    static var showDesktop: GestureAction { .builtin(.showDesktop) }
    static var previousSpace: GestureAction { .builtin(.previousSpace) }
    static var nextSpace: GestureAction { .builtin(.nextSpace) }
    static var previousTab: GestureAction { .builtin(.previousTab) }
    static var nextTab: GestureAction { .builtin(.nextTab) }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .builtin(let b): return b.title
        case .keystroke: return "Keyboard Shortcut\u{2026}"
        case .openApp: return "Open App\u{2026}"
        case .runShortcut: return "Run Shortcut\u{2026}"
        }
    }

    /// A short description of the configured action, e.g. "⌘⇧T" or "Safari".
    var summary: String {
        switch self {
        case .keystroke(let key, let modifiers):
            return key.isEmpty ? "Keyboard Shortcut" : KeyCodes.display(key: key, modifiers: modifiers)
        case .openApp(let bundleID):
            return bundleID.isEmpty ? "Open App" : AppInfo(bundleID: bundleID).name
        case .runShortcut(let name):
            return name.isEmpty ? "Run Shortcut" : "“\(name)”"
        default:
            return displayName
        }
    }

    /// Actions that take input, offered at the end of the picker with empty values.
    static let customCases: [GestureAction] = [
        .keystroke(key: "", modifiers: []), .openApp(bundleID: ""), .runShortcut(name: ""),
    ]

    /// Collapses associated values so a Picker can match the selected row.
    var pickerValue: GestureAction {
        switch self {
        case .openApp: return .openApp(bundleID: "")
        case .keystroke: return .keystroke(key: "", modifiers: [])
        case .runShortcut: return .runShortcut(name: "")
        default: return self
        }
    }

    /// Picking a category again keeps the existing key / app / shortcut.
    func replacing(withPicked picked: GestureAction) -> GestureAction {
        switch (picked, self) {
        case (.openApp, .openApp), (.keystroke, .keystroke), (.runShortcut, .runShortcut): return self
        default: return picked
        }
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case type, key, modifiers, bundleID, name
    }

    private var typeName: String {
        switch self {
        case .none: return "none"
        case .builtin(let b): return b.rawValue
        case .keystroke: return "keystroke"
        case .openApp: return "openApp"
        case .runShortcut: return "runShortcut"
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(typeName, forKey: .type)
        switch self {
        case .keystroke(let key, let modifiers):
            try container.encode(key, forKey: .key)
            try container.encode(modifiers.rawValue, forKey: .modifiers)
        case .openApp(let bundleID):
            try container.encode(bundleID, forKey: .bundleID)
        case .runShortcut(let name):
            try container.encode(name, forKey: .name)
        default:
            break
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "keystroke":
            let key = try container.decode(String.self, forKey: .key)
            let raw = try container.decode(UInt.self, forKey: .modifiers)
            self = .keystroke(key: key, modifiers: NSEvent.ModifierFlags(rawValue: raw))
        case "openApp":
            self = .openApp(bundleID: try container.decode(String.self, forKey: .bundleID))
        case "runShortcut":
            self = .runShortcut(name: try container.decode(String.self, forKey: .name))
        default:
            self = BuiltinAction(rawValue: type).map(GestureAction.builtin) ?? .none
        }
    }

    // MARK: Equatable / Hashable (ModifierFlags isn't Hashable)

    static func == (lhs: GestureAction, rhs: GestureAction) -> Bool {
        switch (lhs, rhs) {
        case (.keystroke(let k1, let m1), .keystroke(let k2, let m2)):
            return k1 == k2 && m1.rawValue == m2.rawValue
        case (.openApp(let b1), .openApp(let b2)):
            return b1 == b2
        case (.runShortcut(let n1), .runShortcut(let n2)):
            return n1 == n2
        default:
            return lhs.typeName == rhs.typeName
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(typeName)
        switch self {
        case .keystroke(let key, let modifiers):
            hasher.combine(key)
            hasher.combine(modifiers.rawValue)
        case .openApp(let bundleID):
            hasher.combine(bundleID)
        case .runShortcut(let name):
            hasher.combine(name)
        default:
            break
        }
    }
}
