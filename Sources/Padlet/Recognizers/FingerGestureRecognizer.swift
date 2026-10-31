// Recognizers/FingerGestureRecognizer.swift
// Multi-finger taps / clicks and corner force clicks.
//
//   • 3 or 4 fingers down and up within `tapMaxDuration`        → Tap
//   • 3 or 4 fingers held for `clickMinDuration`                 → Click (fires while held)
//     The finger count is the most fingers seen during the touch, so a 4-finger tap whose
//     fingers land one by one is still a 4-finger tap.
//   • One finger pressing past `forceThreshold` in a corner zone → Force Click (corner)
//
// Pure logic: frames in, FingerEvents out (on the calling thread). No system calls.

import Foundation

enum FingerEvent: Equatable {
    case gesture(GestureSlot)
    /// A force click is about to happen — swallow the OS click it produces.
    case armClickSuppressor
}

struct FingerRecognizerConfig: Equatable {
    var threeFinger = true
    var fourFinger = true
    var forceClick = true
}

final class FingerGestureRecognizer {

    var onEvent: ((FingerEvent) -> Void)?

    private let config = Locked(FingerRecognizerConfig())

    func setConfig(_ newValue: FingerRecognizerConfig) { config.value = newValue }

    // MARK: Thresholds

    var tapMaxDuration: TimeInterval = 0.50
    var clickMinDuration: TimeInterval = 0.18
    /// Minimum gap between gestures — fingers re-registering during lift-off don't re-fire.
    var tapCooldown: Double = 0.50
    /// Normal touches sit around zTotal 0.71–0.79.
    var forceThreshold: Float = 0.85
    /// Armed slightly earlier so the suppressor beats the OS mouse-down.
    var forcePreArmThreshold: Float = 0.81
    var cornerZoneSize: Float = 0.30
    var dragVelocityThreshold: Float = 0.8
    /// Two or more contacts moving faster than this = scrolling / swiping, not a tap.
    var scrollVelocityThreshold: Float = 0.15

    // Palm rejection
    var palmSizeThreshold: Float = 0.7
    var palmEccentricityThreshold: Float = 3.0
    var edgeProximityZone: Float = 0.05
    var edgePalmSizeThreshold: Float = 0.5

    // MARK: State (multitouch thread)

    private var sessionStart: Double?
    private var sessionFired = false
    private var maxCount = 0
    private var lastFire: Double = -.infinity
    private var forceClickFired: Set<Int32> = []

    // MARK: Input

    func process(fingers: [MTFinger], timestamp: Double) {
        let c = config.value
        let valid = fingers.filter(isFingerContact)

        if c.threeFinger || c.fourFinger {
            processMultiFinger(valid, timestamp: timestamp, config: c)
        } else {
            resetSession()
        }

        if c.forceClick {
            processForceClick(valid)
        } else {
            forceClickFired.removeAll()
        }
    }

    // MARK: Palm rejection

    func isFingerContact(_ finger: MTFinger) -> Bool {
        if finger.size > palmSizeThreshold { return false }
        if finger.minorAxis > 0, finger.majorAxis / finger.minorAxis > palmEccentricityThreshold { return false }
        let p = finger.normalized.position
        let nearEdge = p.x < edgeProximityZone || p.x > 1 - edgeProximityZone
                    || p.y < edgeProximityZone || p.y > 1 - edgeProximityZone
        return !(nearEdge && finger.size > edgePalmSizeThreshold)
    }

    // MARK: Multi-finger tap / click

    private func processMultiFinger(_ fingers: [MTFinger], timestamp: Double, config c: FingerRecognizerConfig) {
        let count = fingers.count

        guard count >= 3 else {
            // Fingers dropped below 3: a short session that never clicked is a tap.
            if let start = sessionStart {
                if !sessionFired && timestamp - start < tapMaxDuration {
                    emit(maxCount >= 4 ? .fourFingerTap : .threeFingerTap, config: c)
                    lastFire = timestamp
                }
                resetSession()
            }
            return
        }

        let moving = fingers.filter { speed($0) > scrollVelocityThreshold }.count
        if moving >= 2 {
            // Scrolling / swiping (incl. the system's 3- and 4-finger swipes) — never a tap.
            resetSession()
            return
        }

        if sessionStart == nil && timestamp - lastFire > tapCooldown {
            sessionStart = timestamp
            sessionFired = false
            maxCount = count
        }
        guard let start = sessionStart else { return }
        maxCount = max(maxCount, count)

        if !sessionFired && timestamp - start >= clickMinDuration {
            sessionFired = true
            lastFire = timestamp
            emit(maxCount >= 4 ? .fourFingerClick : .threeFingerClick, config: c)
        }
    }

    private func resetSession() {
        sessionStart = nil
        sessionFired = false
        maxCount = 0
    }

    private func emit(_ slot: GestureSlot, config c: FingerRecognizerConfig) {
        let enabled = slot.family == .fourFinger ? c.fourFinger : c.threeFinger
        if enabled { onEvent?(.gesture(slot)) }
    }

    // MARK: Corner force click

    private func processForceClick(_ fingers: [MTFinger]) {
        forceClickFired.formIntersection(fingers.map(\.identifier))

        for finger in fingers where !forceClickFired.contains(finger.identifier) {
            guard speed(finger) < dragVelocityThreshold else { continue }
            let p = finger.normalized.position
            guard let corner = cornerSlot(x: p.x, y: p.y) else { continue }

            if finger.zTotal >= forcePreArmThreshold {
                onEvent?(.armClickSuppressor)
            }
            if finger.zTotal >= forceThreshold {
                onEvent?(.gesture(corner))
                forceClickFired.insert(finger.identifier)
            }
        }
    }

    private func cornerSlot(x: Float, y: Float) -> GestureSlot? {
        let z = cornerZoneSize
        switch (x < z, x > 1 - z, y > 1 - z, y < z) {
        case (true, _, true, _): return .cornerTopLeft
        case (_, true, true, _): return .cornerTopRight
        case (true, _, _, true): return .cornerBottomLeft
        case (_, true, _, true): return .cornerBottomRight
        default: return nil
        }
    }

    private func speed(_ f: MTFinger) -> Float {
        let v = f.normalized.velocity
        return (v.x * v.x + v.y * v.y).squareRoot()
    }
}
