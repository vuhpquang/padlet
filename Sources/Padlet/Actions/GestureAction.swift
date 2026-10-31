// Actions/GestureAction.swift
// Everything a mapped gesture can do. Persisted as {"type": "...", ...} JSON.

import AppKit
import Foundation

enum GestureAction: Codable, Equatable, CaseIterable, Hashable {
    case none
    case middleClick
    case keystroke(key: String, modifiers: NSEvent.ModifierFlags)
    case openApp(bundleID: String)
    case missionControl
    case appExpose
    case showDesktop
    case previousSpace
    case nextSpace
    case previousTab
    case nextTab

    var displayName: String {
        switch self {
        case .none:           return "None"
        case .middleClick:    return "Middle Click"
        case .keystroke:      return "Keystroke\u{2026}"
        case .openApp:        return "Open App\u{2026}"
        case .missionControl: return "Mission Control"
        case .appExpose:      return "App Exposé"
        case .showDesktop:    return "Show Desktop"
        case .previousSpace:  return "Previous Space"
        case .nextSpace:      return "Next Space"
        case .previousTab:    return "Previous Tab"
        case .nextTab:        return "Next Tab"
        }
    }

    /// Picker order. Cases with associated values appear once, with empty values.
    static var allCases: [GestureAction] {
        [.none, .middleClick, .missionControl, .appExpose, .showDesktop,
         .previousSpace, .nextSpace, .previousTab, .nextTab,
         .keystroke(key: "", modifiers: []), .openApp(bundleID: "")]
    }

    /// Collapses associated values so a Picker can match the selected row.
    var pickerValue: GestureAction {
        switch self {
        case .openApp:   return .openApp(bundleID: "")
        case .keystroke: return .keystroke(key: "", modifiers: [])
        default:         return self
        }
    }

    /// Picking a category again keeps the existing key / app.
    func replacing(withPicked picked: GestureAction) -> GestureAction {
        switch (picked, self) {
        case (.openApp, .openApp), (.keystroke, .keystroke): return self
        default: return picked
        }
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case type, key, modifiers, bundleID
    }

    private var typeName: String {
        switch self {
        case .none: return "none"
        case .middleClick: return "middleClick"
        case .keystroke: return "keystroke"
        case .openApp: return "openApp"
        case .missionControl: return "missionControl"
        case .appExpose: return "appExpose"
        case .showDesktop: return "showDesktop"
        case .previousSpace: return "previousSpace"
        case .nextSpace: return "nextSpace"
        case .previousTab: return "previousTab"
        case .nextTab: return "nextTab"
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
        default:
            break
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "middleClick":    self = .middleClick
        case "missionControl": self = .missionControl
        case "appExpose":      self = .appExpose
        case "showDesktop":    self = .showDesktop
        case "previousSpace":  self = .previousSpace
        case "nextSpace":      self = .nextSpace
        case "previousTab":    self = .previousTab
        case "nextTab":        self = .nextTab
        case "keystroke":
            let key = try container.decode(String.self, forKey: .key)
            let raw = try container.decode(UInt.self, forKey: .modifiers)
            self = .keystroke(key: key, modifiers: NSEvent.ModifierFlags(rawValue: raw))
        case "openApp":
            self = .openApp(bundleID: try container.decode(String.self, forKey: .bundleID))
        default:
            self = .none
        }
    }

    // MARK: Equatable / Hashable (ModifierFlags isn't Hashable)

    static func == (lhs: GestureAction, rhs: GestureAction) -> Bool {
        switch (lhs, rhs) {
        case (.keystroke(let k1, let m1), .keystroke(let k2, let m2)):
            return k1 == k2 && m1.rawValue == m2.rawValue
        case (.openApp(let b1), .openApp(let b2)):
            return b1 == b2
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
        default:
            break
        }
    }
}
