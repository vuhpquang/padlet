// Settings/GestureMapping.swift
// Which action each mappable gesture triggers.
//
// Stored in UserDefaults under "gestureMapping" as a flat JSON object keyed by
// GestureSlot raw value — the same shape the original six-field struct used, so old
// saves load unchanged and new slots simply fall back to their defaults.

import Foundation

// MARK: - GestureFamily

/// Gestures are switched on/off per family (FeatureFlags).
enum GestureFamily: String, CaseIterable {
    case threeFinger, fourFinger, cornerForceClick, topEdge
    case twoFingerEdgeSwipe, threeFingerEdgeSwipe
}

// MARK: - GestureSlot

enum GestureSlot: String, CaseIterable, Codable, Identifiable {
    case threeFingerTap, threeFingerClick
    case fourFingerTap, fourFingerClick
    case cornerTopLeft, cornerTopRight, cornerBottomLeft, cornerBottomRight
    case topEdgeSwipeLeft, topEdgeSwipeRight
    case twoFingerFromLeft, twoFingerFromRight, twoFingerFromTop, twoFingerFromBottom
    case threeFingerFromLeft, threeFingerFromRight, threeFingerFromTop, threeFingerFromBottom

    var id: String { rawValue }

    var family: GestureFamily {
        switch self {
        case .threeFingerTap, .threeFingerClick: return .threeFinger
        case .fourFingerTap, .fourFingerClick: return .fourFinger
        case .cornerTopLeft, .cornerTopRight, .cornerBottomLeft, .cornerBottomRight: return .cornerForceClick
        case .topEdgeSwipeLeft, .topEdgeSwipeRight: return .topEdge
        case .twoFingerFromLeft, .twoFingerFromRight, .twoFingerFromTop, .twoFingerFromBottom:
            return .twoFingerEdgeSwipe
        case .threeFingerFromLeft, .threeFingerFromRight, .threeFingerFromTop, .threeFingerFromBottom:
            return .threeFingerEdgeSwipe
        }
    }

    /// Short label used inside a family's section.
    var shortTitle: String {
        switch self {
        case .threeFingerTap, .fourFingerTap: return "Tap"
        case .threeFingerClick, .fourFingerClick: return "Click (hold)"
        case .cornerTopLeft: return "Top Left"
        case .cornerTopRight: return "Top Right"
        case .cornerBottomLeft: return "Bottom Left"
        case .cornerBottomRight: return "Bottom Right"
        case .topEdgeSwipeLeft: return "Swipe Left"
        case .topEdgeSwipeRight: return "Swipe Right"
        case .twoFingerFromLeft, .threeFingerFromLeft: return "From Left Edge"
        case .twoFingerFromRight, .threeFingerFromRight: return "From Right Edge"
        case .twoFingerFromTop, .threeFingerFromTop: return "From Top Edge"
        case .twoFingerFromBottom, .threeFingerFromBottom: return "From Bottom Edge"
        }
    }

    /// Full label used where the family isn't obvious (app profiles).
    var title: String {
        switch family {
        case .threeFinger: return "Three Finger \(shortTitle)"
        case .fourFinger: return "Four Finger \(shortTitle)"
        case .cornerForceClick: return "Force Click \(shortTitle)"
        case .topEdge: return "Top Edge \(shortTitle)"
        case .twoFingerEdgeSwipe: return "Two Finger Swipe \(shortTitle)"
        case .threeFingerEdgeSwipe: return "Three Finger Swipe \(shortTitle)"
        }
    }

    static func slots(in family: GestureFamily) -> [GestureSlot] {
        allCases.filter { $0.family == family }
    }

    /// The edge-swipe slot for a finger count (2 or 3) and the edge the swipe starts from.
    static func edgeSwipe(fingers: Int, from edge: TrackpadEdge) -> GestureSlot? {
        switch (fingers, edge) {
        case (2, .left): return .twoFingerFromLeft
        case (2, .right): return .twoFingerFromRight
        case (2, .top): return .twoFingerFromTop
        case (2, .bottom): return .twoFingerFromBottom
        case (3, .left): return .threeFingerFromLeft
        case (3, .right): return .threeFingerFromRight
        case (3, .top): return .threeFingerFromTop
        case (3, .bottom): return .threeFingerFromBottom
        default: return nil
        }
    }
}

// MARK: - GestureMapping

struct GestureMapping: Equatable {

    private(set) var actions: [GestureSlot: GestureAction]

    subscript(slot: GestureSlot) -> GestureAction {
        get { actions[slot] ?? Self.defaultAction(for: slot) }
        set { actions[slot] = newValue }
    }

    static func defaultAction(for slot: GestureSlot) -> GestureAction {
        switch slot {
        case .threeFingerTap: return .middleClick
        case .cornerTopLeft: return .missionControl
        case .topEdgeSwipeLeft: return .previousSpace
        case .topEdgeSwipeRight: return .nextSpace
        default: return .none
        }
    }

    static var defaults: GestureMapping {
        GestureMapping(actions: Dictionary(uniqueKeysWithValues: GestureSlot.allCases.map { ($0, defaultAction(for: $0)) }))
    }

    // MARK: Persistence

    private static let storageKey = "gestureMapping"

    static func load(from defaults: UserDefaults = .standard) -> GestureMapping {
        guard let data = defaults.data(forKey: storageKey) else { return .defaults }
        do {
            return try JSONDecoder().decode(GestureMapping.self, from: data)
        } catch {
            Log.error("GestureMapping: could not decode saved mapping (\(error)); using defaults.")
            return .defaults
        }
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

// MARK: - Codable (flat object keyed by slot)

extension GestureMapping: Codable {

    private struct SlotKey: CodingKey {
        let stringValue: String
        init(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SlotKey.self)
        var result = GestureMapping.defaults
        for slot in GestureSlot.allCases {
            if let action = try? container.decodeIfPresent(GestureAction.self, forKey: SlotKey(stringValue: slot.rawValue)) {
                result[slot] = action
            }
        }
        self = result
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: SlotKey.self)
        for slot in GestureSlot.allCases {
            try container.encode(self[slot], forKey: SlotKey(stringValue: slot.rawValue))
        }
    }
}
