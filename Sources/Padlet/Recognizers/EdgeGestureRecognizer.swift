// Recognizers/EdgeGestureRecognizer.swift
// Single-finger gestures that start on the trackpad's edges:
//
//   ┌── top strip: flick ← → (mapped action) / drag ← → (app switcher) ──┬──┐
//   │▒                                                          │●●│ double-tap: mute
//   │▒ left edge: slide ↕                    right edge: slide ↕│ ▒│
//   │▒ (EdgeFunction)                            (EdgeFunction) │ ▒│
//   └──────── bottom strip: swipe ← → tracks, double-tap play ──┴──┘
//
// A touch only counts if it STARTS in a zone with exactly one finger down. A side-edge
// touch becomes a slide once it moves mostly vertically by `commitDistance`; moving
// sideways first means it's an ordinary pointer move and is left alone. A second finger
// cancels (scroll / pinch).
//
// Top strip with the app switcher on: a flick (lifted within `topSwipeMaxDuration`) still
// fires the mapped action; a touch held longer that moves sideways scrubs through apps,
// one app per `switcherStep`, and lifting picks the selected one.
//
// Pure logic: frames in, EdgeEvents out (on the calling thread). The clock, modifier
// keys and pointer location are injected so tests can drive it.

import CoreGraphics
import Foundation

enum EdgeTapZone: Equatable {
    case muteCorner, mediaStrip
}

enum EdgeEvent: Equatable {
    /// `anchor` is where to pin the pointer (nil = don't freeze).
    case slideBegan(EdgeFunction, anchor: CGPoint?)
    /// `delta` is already scaled by sensitivity; `fine` = quarter-step mode.
    case slid(EdgeFunction, delta: Float, fine: Bool)
    case slideEnded
    case mediaSwipe(forward: Bool, restore: CGPoint?)
    case topSwipe(GestureSlot, restore: CGPoint?)
    /// App switcher opened; `anchor` is where to pin the pointer (nil = don't freeze).
    case switcherBegan(anchor: CGPoint?)
    /// Selection moved: `offset` apps from the frontmost one (may be negative; wraps).
    case switcherMoved(offset: Int)
    /// Finger lifted (`commit` = switch to the selection) or the touch was cancelled.
    case switcherEnded(commit: Bool)
    case doubleTap(EdgeTapZone)
    /// The second tap of a double tap is landing — swallow its tap-to-click.
    case armClickSuppressor
}

struct EdgeRecognizerConfig: Equatable {
    var settings = EdgeSettings()
    var edgeControls = true
    var topEdge = true
}

final class EdgeGestureRecognizer {

    var onEvent: ((EdgeEvent) -> Void)?

    private let config = Locked(EdgeRecognizerConfig())
    private let lastKeyPress = Locked<TimeInterval>(-.infinity)

    private let now: () -> TimeInterval
    private let modifiers: () -> CGEventFlags
    private let pointer: () -> CGPoint?

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         modifiers: @escaping () -> CGEventFlags = { CGEventSource.flagsState(.combinedSessionState) },
         pointer: @escaping () -> CGPoint? = { CGEvent(source: nil)?.location }) {
        self.now = now
        self.modifiers = modifiers
        self.pointer = pointer
    }

    func setConfig(_ newValue: EdgeRecognizerConfig) { config.value = newValue }

    /// Called from a global keyDown monitor; drives the typing guard.
    func noteKeyPress() { lastKeyPress.value = now() }

    // MARK: Tunables (normalized trackpad units / seconds)

    let commitDistance: Float = 0.015
    let horizontalAbort: Float = 0.06
    let tapMaxDuration: Double = 0.25
    let tapMaxTravel: Float = 0.02
    let doubleTapWindow: Double = 0.45
    let stripHeight: Float = 0.08
    let muteCornerSize: Float = 0.12
    let swipeDistance: Float = 0.12
    /// Top swipes must be quick flicks — slow horizontal moves along the top are pointer moves.
    let topSwipeMaxDuration: Double = 0.4
    let stripVerticalAbort: Float = 0.1
    /// Sideways travel that opens the app switcher (after the flick window).
    let switcherCommit: Float = 0.03
    /// Sideways travel per app while switching.
    let switcherStep: Float = 0.07
    let bottomQuarter: Float = 0.25
    let palmSize: Float = 0.7
    let outOfRangeState: Int32 = 7

    // MARK: State (multitouch thread)

    private enum Zone: Equatable { case muteCorner, mediaStrip, topStrip }

    private struct Touch {
        let id: Int32
        let start: MTPoint
        let startTime: Double
        let sideIsLeft: Bool?   // may become a slide on this edge
        let zone: Zone?         // may become a tap / swipe
        let anchor: CGPoint?
        var lastY: Float
        var lastPoint: MTPoint
        var maxTravel: Float = 0
        var sliding = false
        var switching = false
        var switchOriginX: Float = 0
        var switchDirection = 1
        var switchOffset = 0
        var swiped = false
        var cancelled = false
        var function: EdgeFunction = .off
    }

    private var touch: Touch?
    /// Contacts that may not start a gesture (part of a multi-finger touch, or already tried).
    private var ineligible: Set<Int32> = []
    private var lastTap: (zone: EdgeTapZone, time: Double)?

    // MARK: Input

    func process(fingers: [MTFinger], timestamp: Double) {
        let c = config.value
        let live = fingers.filter { $0.state != outOfRangeState }
        let ids = Set(live.map(\.identifier))
        ineligible.formIntersection(ids)
        if live.count > 1 { ineligible.formUnion(ids) }

        if var t = touch {
            guard let f = live.first(where: { $0.identifier == t.id }) else {
                finish(t, timestamp: timestamp, config: c)
                touch = nil
                return
            }
            if live.count > 1 && !t.cancelled {
                t.cancelled = true
                if t.sliding { onEvent?(.slideEnded) }
                if t.switching { onEvent?(.switcherEnded(commit: false)) }
            }
            if !t.cancelled { update(&t, finger: f, timestamp: timestamp, config: c) }
            touch = t
            return
        }

        guard live.count == 1, let f = live.first, !ineligible.contains(f.identifier) else { return }
        ineligible.insert(f.identifier)   // one chance per contact
        touch = begin(f, timestamp: timestamp, config: c)
    }

    // MARK: Begin

    private func begin(_ f: MTFinger, timestamp: Double, config c: EdgeRecognizerConfig) -> Touch? {
        let s = c.settings
        guard f.size <= palmSize, now() - lastKeyPress.value >= s.typingGuardMs / 1000 else { return nil }

        let p = f.normalized.position
        let w = Float(s.edgeWidth)
        let inMiddle = p.x >= w && p.x <= 1 - w

        var sideIsLeft: Bool?
        if c.edgeControls {
            if p.x < w { sideIsLeft = true } else if p.x > 1 - w { sideIsLeft = false }
            if let left = sideIsLeft {
                let modifierHeld = modifiers().contains(.maskSecondaryFn) || modifiers().contains(.maskAlternate)
                if s.function(forLeftEdge: left) == .off
                    || (s.bottomQuarterOnly && p.y > bottomQuarter)
                    || (s.requireModifier && !modifierHeld) {
                    sideIsLeft = nil
                }
            }
        }

        var zone: Zone?
        let inMuteCorner = p.x > 1 - muteCornerSize && p.y > 1 - muteCornerSize
        if c.edgeControls && s.quickMute && inMuteCorner {
            zone = .muteCorner
        } else if c.edgeControls && (s.mediaStrip || s.mediaTap) && p.y < stripHeight && inMiddle {
            zone = .mediaStrip
        } else if c.topEdge && p.y > 1 - stripHeight && inMiddle && !inMuteCorner {
            zone = .topStrip
        }

        guard sideIsLeft != nil || zone != nil else { return nil }

        // Second tap of a double tap: swallow the tap-to-click it would produce.
        if let tapZone = zone.flatMap(Self.tapZone), let last = lastTap,
           last.zone == tapZone, timestamp - last.time < doubleTapWindow,
           tapZone == .muteCorner || s.mediaTap {
            onEvent?(.armClickSuppressor)
        }

        return Touch(id: f.identifier, start: p, startTime: timestamp,
                     sideIsLeft: sideIsLeft, zone: zone,
                     anchor: pointer(), lastY: p.y, lastPoint: p)
    }

    private static func tapZone(_ zone: Zone) -> EdgeTapZone? {
        switch zone {
        case .muteCorner: return .muteCorner
        case .mediaStrip: return .mediaStrip
        case .topStrip: return nil
        }
    }

    // MARK: Update

    private func update(_ t: inout Touch, finger f: MTFinger, timestamp: Double, config c: EdgeRecognizerConfig) {
        let s = c.settings
        let p = f.normalized.position
        let dx = p.x - t.start.x
        let dy = p.y - t.start.y
        t.maxTravel = max(t.maxTravel, (dx * dx + dy * dy).squareRoot())
        t.lastPoint = p

        if t.sliding {
            let fine = s.fineControlAlways
                || (modifiers().contains(.maskShift) && modifiers().contains(.maskAlternate))
            let delta = (p.y - t.lastY) * Float(s.sensitivity) / (fine ? 4 : 1)
            t.lastY = p.y
            if delta != 0 { onEvent?(.slid(t.function, delta: delta, fine: fine)) }
            return
        }
        if t.switching {
            let steps = Int(((p.x - t.switchOriginX) / switcherStep).rounded(.towardZero))
            let offset = t.switchDirection + steps
            if offset != t.switchOffset {
                t.switchOffset = offset
                onEvent?(.switcherMoved(offset: offset))
            }
            return
        }
        if t.swiped { return }

        let horizontalSwipe = abs(dx) > swipeDistance && abs(dx) > 2 * abs(dy)
        let restore = s.freezeCursor ? t.anchor : nil

        switch t.zone {
        case .mediaStrip where horizontalSwipe && s.mediaStrip:
            t.swiped = true
            onEvent?(.mediaSwipe(forward: (dx > 0) != s.invertMediaSwipe, restore: restore))
            return
        case .topStrip where s.topAppSwitcher:
            // Flicks are decided on lift; a held touch that moves sideways switches apps.
            if timestamp - t.startTime > topSwipeMaxDuration,
               abs(dx) > switcherCommit, abs(dx) > abs(dy) {
                t.switching = true
                t.switchDirection = dx > 0 ? 1 : -1
                t.switchOriginX = p.x
                t.switchOffset = t.switchDirection
                onEvent?(.switcherBegan(anchor: s.freezeCursor ? t.anchor : nil))
                onEvent?(.switcherMoved(offset: t.switchOffset))
                return
            }
        case .topStrip where horizontalSwipe:
            t.swiped = true
            if timestamp - t.startTime <= topSwipeMaxDuration {
                onEvent?(.topSwipe(dx > 0 ? .topEdgeSwipeRight : .topEdgeSwipeLeft, restore: restore))
            }
            return
        default:
            break
        }

        if let left = t.sideIsLeft, abs(dy) > commitDistance, abs(dy) > abs(dx) {
            t.sliding = true
            t.lastY = p.y
            t.function = s.function(forLeftEdge: left)
            onEvent?(.slideBegan(t.function, anchor: s.freezeCursor ? t.anchor : nil))
            return
        }

        switch t.zone {
        case .mediaStrip, .topStrip:
            if abs(dy) > stripVerticalAbort { t.cancelled = true }
        default:
            if abs(dx) > horizontalAbort { t.cancelled = true }
        }
    }

    // MARK: End

    private func finish(_ t: Touch, timestamp: Double, config c: EdgeRecognizerConfig) {
        if t.sliding {
            if !t.cancelled { onEvent?(.slideEnded) }
            return
        }
        if t.switching {
            if !t.cancelled { onEvent?(.switcherEnded(commit: true)) }
            return
        }
        if t.zone == .topStrip, c.settings.topAppSwitcher, !t.cancelled,
           timestamp - t.startTime <= topSwipeMaxDuration {
            let dx = t.lastPoint.x - t.start.x
            let dy = t.lastPoint.y - t.start.y
            if abs(dx) > swipeDistance && abs(dx) > 2 * abs(dy) {
                onEvent?(.topSwipe(dx > 0 ? .topEdgeSwipeRight : .topEdgeSwipeLeft,
                                   restore: c.settings.freezeCursor ? t.anchor : nil))
            }
            return
        }
        guard !t.swiped, !t.cancelled,
              let tapZone = t.zone.flatMap(Self.tapZone),
              timestamp - t.startTime < tapMaxDuration,
              t.maxTravel < tapMaxTravel else { return }

        let enabled = tapZone == .muteCorner ? c.settings.quickMute : c.settings.mediaTap
        guard enabled else { return }

        if let last = lastTap, last.zone == tapZone, timestamp - last.time < doubleTapWindow {
            lastTap = nil
            onEvent?(.doubleTap(tapZone))
        } else {
            lastTap = (tapZone, timestamp)
        }
    }
}
