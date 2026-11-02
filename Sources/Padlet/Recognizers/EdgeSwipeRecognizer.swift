// Recognizers/EdgeSwipeRecognizer.swift
// Two- and three-finger swipes that start at a trackpad edge and move inward
// (like the system's two-finger swipe in from the right edge for Notification Center).
//
//   • 2 or 3 fingers land, all within `edgeZone` of the same edge,
//     within `landingWindow` of the first contact
//   • the centroid then travels `minDistance` inward, mostly straight in,
//     within `maxDuration`                                         → swipe (once per touch)
//
// Lifting a finger, adding a fourth, or starting away from an edge cancels the touch until
// every finger is up. Normalized coordinates: x = 0 left, y = 0 bottom.
//
// Pure logic: frames in, GestureSlots out (on the calling thread). No system calls.

import Foundation

enum TrackpadEdge: CaseIterable, Equatable {
    case left, right, top, bottom

    /// Unit vector pointing from this edge into the trackpad.
    var inward: (x: Float, y: Float) {
        switch self {
        case .left: return (1, 0)
        case .right: return (-1, 0)
        case .top: return (0, -1)
        case .bottom: return (0, 1)
        }
    }

    /// Distance of a point from this edge.
    func distance(x: Float, y: Float) -> Float {
        switch self {
        case .left: return x
        case .right: return 1 - x
        case .top: return 1 - y
        case .bottom: return y
        }
    }
}

struct EdgeSwipeRecognizerConfig: Equatable {
    var twoFinger = false
    var threeFinger = false
}

final class EdgeSwipeRecognizer {

    var onGesture: ((GestureSlot) -> Void)?
    /// Palm rejection — the coordinator passes the finger recognizer's filter.
    var isContact: (MTFinger) -> Bool = { _ in true }

    private let config = Locked(EdgeSwipeRecognizerConfig())

    func setConfig(_ newValue: EdgeSwipeRecognizerConfig) { config.value = newValue }

    // MARK: Thresholds

    /// How close to an edge every finger must land.
    var edgeZone: Float = 0.15
    /// All fingers must be down within this long of the first contact.
    var landingWindow: Double = 0.25
    /// Inward travel of the centroid that fires the swipe.
    var minDistance: Float = 0.12
    /// Inward travel must be at least this many times the sideways travel.
    var straightness: Float = 1.2
    /// A swipe slower than this is a drag / scroll, not a swipe.
    var maxDuration: Double = 0.7

    private let outOfRangeState: Int32 = 7

    // MARK: State (multitouch thread)

    private struct Anchor {
        let count: Int
        let edge: TrackpadEdge
        let x: Float
        let y: Float
        let time: Double
    }

    private var firstContact: Double?
    private var anchor: Anchor?
    /// Fired or cancelled — ignore everything until all fingers lift.
    private var done = false

    // MARK: Input

    func process(fingers: [MTFinger], timestamp: Double) {
        let c = config.value
        let live = fingers.filter { $0.state != outOfRangeState && isContact($0) }
        let n = live.count

        guard n > 0 else { reset(); return }
        if firstContact == nil { firstContact = timestamp }
        guard !done else { return }
        guard c.twoFinger || c.threeFinger else { done = true; return }

        if n > 3 { done = true; return }

        let (cx, cy) = centroid(live)

        if let a = anchor, n < a.count { done = true; return }   // a finger lifted early

        if anchor == nil || n > anchor!.count {
            guard n >= 2 else { return }                         // wait for the second finger
            guard let start = firstContact, timestamp - start <= landingWindow,
                  let edge = commonEdge(live, cx: cx, cy: cy) else { done = true; return }
            anchor = Anchor(count: n, edge: edge, x: cx, y: cy, time: timestamp)
            return
        }

        guard let a = anchor else { return }
        if timestamp - a.time > maxDuration { done = true; return }

        let dx = cx - a.x, dy = cy - a.y
        let v = a.edge.inward
        let inward = dx * v.x + dy * v.y
        let sideways = abs(dx * v.y - dy * v.x)
        guard inward >= minDistance, inward >= sideways * straightness else { return }

        done = true
        let enabled = a.count == 2 ? c.twoFinger : c.threeFinger
        if enabled, let slot = GestureSlot.edgeSwipe(fingers: a.count, from: a.edge) {
            onGesture?(slot)
        }
    }

    // MARK: Helpers

    private func reset() {
        firstContact = nil
        anchor = nil
        done = false
    }

    private func centroid(_ fingers: [MTFinger]) -> (Float, Float) {
        let n = Float(fingers.count)
        let sx = fingers.reduce(Float(0)) { $0 + $1.normalized.position.x }
        let sy = fingers.reduce(Float(0)) { $0 + $1.normalized.position.y }
        return (sx / n, sy / n)
    }

    /// The edge every finger is near; in a corner, the one the centroid is closest to.
    private func commonEdge(_ fingers: [MTFinger], cx: Float, cy: Float) -> TrackpadEdge? {
        TrackpadEdge.allCases
            .filter { edge in
                fingers.allSatisfy { edge.distance(x: $0.normalized.position.x, y: $0.normalized.position.y) <= edgeZone }
            }
            .min { $0.distance(x: cx, y: cy) < $1.distance(x: cx, y: cy) }
    }
}
