// Core/EdgeGestureRecognizer.swift
// Turns the edges of the trackpad into controls (the EdgeBar idea):
//
//   ┌──────────────────────────────────────┬──┐
//   │▒                                     │●●│ ← double-tap: mute / unmute
//   │▒                                     │ ▒│
//   │▒ brightness                   volume │ ▒│   slide one finger up/down
//   │▒                                     │ ▒│   along a side edge
//   │▒   ◀── swipe: prev / next track ──▶  │ ▒│
//   └──────────────────────────────────────┴──┘
//         bottom strip (double-tap: play/pause, off by default)
//
// Only single-finger touches that START inside a zone are considered. A touch is
// "committed" to a slide only once it moves mostly vertically by a small distance, so
// a normal pointer move that happens to start near an edge is left alone. A second
// finger landing at any point cancels (that's a scroll or a pinch).
//
// Runs on the multitouch callback thread; every system call is hopped to main.

import AppKit
import CoreGraphics
import Foundation

final class EdgeGestureRecognizer {

    // MARK: - Settings (written on main, read on the multitouch thread)

    private let lock = NSLock()
    private var _settings = EdgeSettings()
    private var _lastKeyPress: TimeInterval = 0

    var settings: EdgeSettings {
        get { lock.lock(); defer { lock.unlock() }; return _settings }
        set { lock.lock(); _settings = newValue; lock.unlock() }
    }

    /// Called from a global keyDown monitor; drives the typing guard.
    func noteKeyPress() {
        lock.lock()
        _lastKeyPress = ProcessInfo.processInfo.systemUptime
        lock.unlock()
    }

    // MARK: - Tunables (normalized trackpad units, seconds)

    private let commitDistance: Float = 0.015     // vertical travel that commits a slide
    private let horizontalAbort: Float = 0.06     // sideways travel that means "pointer move"
    private let tapMaxDuration: Double = 0.25
    private let tapMaxTravel: Float = 0.02
    private let doubleTapWindow: Double = 0.45
    private let mediaStripHeight: Float = 0.08
    private let muteCornerSize: Float = 0.12
    private let mediaSwipeDistance: Float = 0.12
    private let bottomQuarter: Float = 0.25
    private let palmSize: Float = 0.7
    private let outOfRangeState: Int32 = 7
    private let coarseSteps: Float = 16
    private let fineSteps: Float = 64

    // MARK: - State (multitouch thread only)

    private enum Side { case left, right }
    private enum TapZone { case muteCorner, mediaStrip }
    private enum Target { case volume, brightness }

    private struct Touch {
        let id: Int32
        let startPos: MTPoint
        let startTime: Double
        let side: Side?            // may become an edge slide
        let tapZone: TapZone?      // may become a tap / swipe
        let cursorAnchor: CGPoint? // pointer position at touch-down
        var lastY: Float
        var maxTravel: Float = 0
        var sliding = false
        var swiped = false
        var cancelled = false
        var target: Target = .volume
        var value: Float = 0       // continuous value 0…1 (or key accumulator)
        var lastApplied: Float = 0 // last quantized value sent to the system
        var useKeys = false        // no direct API → step with media keys
    }

    private var touch: Touch?
    /// Contacts that may not start an edge gesture (were part of a multi-finger touch,
    /// or already had their one chance).
    private var ineligible: Set<Int32> = []
    private var lastTap: (zone: TapZone, time: Double)?

    // MARK: - Frame input

    func process(fingers: [MTFinger], timestamp: Double) {
        let s = settings
        let live = fingers.filter { $0.state != outOfRangeState }
        let liveIDs = Set(live.map(\.identifier))
        ineligible.formIntersection(liveIDs)
        if live.count > 1 { ineligible.formUnion(liveIDs) }

        if var t = touch {
            guard let f = live.first(where: { $0.identifier == t.id }) else {
                finish(t, timestamp: timestamp, settings: s)
                touch = nil
                return
            }
            if live.count > 1 && !t.cancelled { cancel(&t) }
            if !t.cancelled { update(&t, finger: f, settings: s) }
            touch = t
            return
        }

        guard live.count == 1, let f = live.first, !ineligible.contains(f.identifier) else { return }
        ineligible.insert(f.identifier)   // one chance per contact
        touch = begin(f, timestamp: timestamp, settings: s)
    }

    // MARK: - Begin

    private func begin(_ f: MTFinger, timestamp: Double, settings s: EdgeSettings) -> Touch? {
        guard f.size <= palmSize, !typingGuardActive(s) else { return nil }

        let p = f.normalized.position
        let w = Float(s.edgeWidth)

        var side: Side? = p.x < w ? .left : (p.x > 1 - w ? .right : nil)
        if side != nil {
            if s.bottomQuarterOnly && p.y > bottomQuarter { side = nil }
            if s.requireModifier && !Self.slideModifierHeld() { side = nil }
        }

        var zone: TapZone?
        if s.quickMute && p.x > 1 - muteCornerSize && p.y > 1 - muteCornerSize {
            zone = .muteCorner
        } else if (s.mediaStrip || s.mediaTap) && p.y < mediaStripHeight && p.x >= w && p.x <= 1 - w {
            zone = .mediaStrip
        }

        guard side != nil || zone != nil else { return nil }

        // Second tap of a double tap: swallow the tap-to-click it would otherwise produce.
        if let z = zone, let lt = lastTap, lt.zone == z, timestamp - lt.time < doubleTapWindow,
           z == .muteCorner || s.mediaTap {
            ClickSuppressor.shared.arm(for: 0.5)
        }

        return Touch(id: f.identifier, startPos: p, startTime: timestamp,
                     side: side, tapZone: zone,
                     cursorAnchor: CursorFreezer.currentLocation(),
                     lastY: p.y)
    }

    // MARK: - Update

    private func update(_ t: inout Touch, finger f: MTFinger, settings s: EdgeSettings) {
        let p = f.normalized.position
        let dx = p.x - t.startPos.x
        let dy = p.y - t.startPos.y
        t.maxTravel = max(t.maxTravel, (dx * dx + dy * dy).squareRoot())

        if t.sliding { slide(&t, y: p.y, settings: s); return }
        if t.swiped { return }

        // Bottom strip: horizontal swipe → previous / next track.
        if t.tapZone == .mediaStrip, s.mediaStrip,
           abs(dx) > mediaSwipeDistance, abs(dx) > 2 * abs(dy) {
            t.swiped = true
            let forward = (dx > 0) != s.invertMediaSwipe
            let anchor = s.freezeCursor ? t.cursorAnchor : nil
            DispatchQueue.main.async {
                MediaKeys.post(forward ? .next : .previous)
                if let a = anchor { CGWarpMouseCursorPosition(a) }
            }
            return
        }

        // Side edge: mostly-vertical movement commits a slide.
        if let side = t.side, abs(dy) > commitDistance, abs(dy) > abs(dx) {
            startSlide(&t, side: side, y: p.y, settings: s)
            return
        }

        // Anything else that travels is an ordinary pointer move — let it be.
        if t.tapZone == .mediaStrip {
            if abs(dy) > 0.1 { t.cancelled = true }
        } else if abs(dx) > horizontalAbort {
            t.cancelled = true
        }
    }

    // MARK: - Slide

    private func startSlide(_ t: inout Touch, side: Side, y: Float, settings s: EdgeSettings) {
        t.sliding = true
        t.lastY = y
        t.target = ((side == .right) != s.swapSides) ? .volume : .brightness

        let current = t.target == .volume ? VolumeControl.get() : BrightnessControl.get()
        if let v = current {
            t.value = v
            t.lastApplied = (v * coarseSteps).rounded() / coarseSteps
        } else {
            t.useKeys = true
            t.value = 0
        }

        if s.freezeCursor, let anchor = t.cursorAnchor {
            DispatchQueue.main.async { CursorFreezer.shared.freeze(at: anchor) }
        }
    }

    private func slide(_ t: inout Touch, y: Float, settings s: EdgeSettings) {
        let fine = s.fineControlAlways || Self.fineModifierHeld()
        let steps = fine ? fineSteps : coarseSteps
        let sensitivity = Float(s.sensitivity) / (fine ? 4 : 1)
        let delta = (y - t.lastY) * sensitivity
        t.lastY = y

        let target = t.target
        let haptic = s.haptics

        // Fallback: no direct API — emit one media key per coarse step.
        if t.useKeys {
            t.value += delta
            let step = 1 / coarseSteps
            var keys: [MediaKey] = []
            while t.value >= step { keys.append(target == .volume ? .soundUp : .brightnessUp); t.value -= step }
            while t.value <= -step { keys.append(target == .volume ? .soundDown : .brightnessDown); t.value += step }
            guard !keys.isEmpty else { return }
            DispatchQueue.main.async {
                keys.forEach(MediaKeys.post)
                if haptic { Haptics.tick() }
            }
            return
        }

        t.value = min(max(t.value + delta, 0), 1)
        let q = (t.value * steps).rounded() / steps
        guard q != t.lastApplied else { return }
        t.lastApplied = q

        let chiclets = UInt32(steps)
        DispatchQueue.main.async {
            switch target {
            case .volume:
                VolumeControl.set(q)
                SystemOSD.shared.show(q == 0 ? .muted : .volume, level: q, chiclets: chiclets)
            case .brightness:
                BrightnessControl.set(q)
                SystemOSD.shared.show(.brightness, level: q, chiclets: chiclets)
            }
            if haptic { Haptics.tick() }
        }
    }

    // MARK: - End / cancel

    private func cancel(_ t: inout Touch) {
        t.cancelled = true
        if t.sliding { DispatchQueue.main.async { CursorFreezer.shared.release() } }
    }

    private func finish(_ t: Touch, timestamp: Double, settings s: EdgeSettings) {
        if t.sliding || t.swiped {
            DispatchQueue.main.async { CursorFreezer.shared.release() }
            return
        }
        guard !t.cancelled, let zone = t.tapZone,
              timestamp - t.startTime < tapMaxDuration,
              t.maxTravel < tapMaxTravel else { return }

        let enabled = zone == .muteCorner ? s.quickMute : s.mediaTap
        guard enabled else { return }

        if let lt = lastTap, lt.zone == zone, timestamp - lt.time < doubleTapWindow {
            lastTap = nil
            fireDoubleTap(zone, haptic: s.haptics)
        } else {
            lastTap = (zone, timestamp)
        }
    }

    private func fireDoubleTap(_ zone: TapZone, haptic: Bool) {
        DispatchQueue.main.async {
            switch zone {
            case .muteCorner:
                if let muted = VolumeControl.isMuted(), VolumeControl.setMuted(!muted) {
                    let level = VolumeControl.get() ?? 0
                    SystemOSD.shared.show(!muted ? .muted : .volume, level: !muted ? 0 : level)
                } else {
                    MediaKeys.post(.mute)
                }
            case .mediaStrip:
                MediaKeys.post(.play)
            }
            if haptic { Haptics.tick() }
        }
    }

    // MARK: - Guards / modifiers

    private func typingGuardActive(_ s: EdgeSettings) -> Bool {
        lock.lock()
        let last = _lastKeyPress
        lock.unlock()
        return ProcessInfo.processInfo.systemUptime - last < s.typingGuardMs / 1000
    }

    private static func slideModifierHeld() -> Bool {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        return flags.contains(.maskSecondaryFn) || flags.contains(.maskAlternate)
    }

    private static func fineModifierHeld() -> Bool {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        return flags.contains(.maskShift) && flags.contains(.maskAlternate)
    }
}
