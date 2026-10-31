import AppKit
import Foundation

// MARK: - Corner / GestureEvent

enum Corner: String, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}

enum GestureEvent: Equatable {
    case threeFingerTap
    case threeFingerClick
    case forceClickCorner(Corner)
}

// MARK: - Delegate

protocol GestureRecognizerDelegate: AnyObject {
    func didRecognize(gesture: GestureEvent)
}

// MARK: - GestureRecognizer

class GestureRecognizer {

    weak var delegate: GestureRecognizerDelegate?

    // Per-family switches, set by GestureCoordinator from FeatureFlags.
    // When a family is off its state machine is not run at all, so e.g. a disabled
    // corner force click can no longer arm the ClickSuppressor.
    var threeFingerEnabled = true {
        didSet { if !threeFingerEnabled { threeFingerStart = nil; tapFired = false } }
    }
    var forceClickEnabled = true {
        didSet { if !forceClickEnabled { forceClickFired.removeAll() } }
    }

    // Thresholds
    var tapMaxDuration: TimeInterval = 0.50     // tap must lift within this time
    var clickMinDuration: TimeInterval = 0.18   // held >= this → threeFingerClick, not tap
    var tapCooldown: Double = 0.50              // minimum seconds between successive taps
    var forceThreshold: Float = 0.85            // zTotal to trigger force click; normal touch = ~0.71–0.79
    var cornerZoneSize: Float = 0.30            // 30% of trackpad edge = corner zone
    // Velocity (normalized units/sec) above which a finger is considered to be dragging.
    // Force-click detection is skipped while dragging to avoid mid-drag corner misfires.
    var dragVelocityThreshold: Float = 0.8
    // Velocity threshold for scroll detection. If 2+ contacts exceed this speed when
    // a third contact appears, the third is treated as an incidental palm, not a gesture finger.
    var scrollVelocityThreshold: Float = 0.15

    // Palm rejection thresholds
    // A normal fingertip has size ~0.30; a palm is typically > 0.7.
    var palmSizeThreshold: Float = 0.7
    // Palms are elongated; ratio of majorAxis/minorAxis above this is palm-like.
    var palmEccentricityThreshold: Float = 3.0
    // Contacts near the trackpad edge with above-normal size are likely wrist/palm.
    var edgeProximityZone: Float = 0.05         // 5% of trackpad width/height
    var edgePalmSizeThreshold: Float = 0.5      // size above this at the edge → palm

    // Three-finger tap state
    private var threeFingerStart: Double?
    private var tapFired = false
    private var lastTapTimestamp: Double = 0

    // Force-click state — track per identifier so each new contact can fire once
    private var forceClickFired: Set<Int32> = []
    // Pre-arm threshold: arm the click suppressor as soon as pressure exceeds
    // normal-touch range (~0.79 max), before the OS "click" haptic fires.
    // The gesture fires at forceThreshold (0.85). The gap gives the suppressor
    // time to intercept the leftMouseDown before our gesture fires.
    private let forcePreArmThreshold: Float = 0.81

    // MARK: - Frame input (called by GestureCoordinator on the multitouch thread)

    func process(fingers: [MTFinger], timestamp: Double) {
        // Palm rejection: filter out contacts that are likely palms or wrists.
        let validFingers = fingers.filter { isFingerContact($0) }
        if threeFingerEnabled { processThreeFinger(fingers: validFingers, timestamp: timestamp) }
        if forceClickEnabled { processForceClick(fingers: validFingers) }
    }

    /// Returns true when a contact looks like an intentional fingertip touch.
    /// Filters out palms, wrists, and large incidental contacts.
    private func isFingerContact(_ finger: MTFinger) -> Bool {
        // Reject by size — palms are typically > 1.0.
        if finger.size > palmSizeThreshold { return false }
        // Reject elongated contacts — palms have a high major/minor axis ratio.
        if finger.minorAxis > 0 {
            let eccentricity = finger.majorAxis / finger.minorAxis
            if eccentricity > palmEccentricityThreshold { return false }
        }
        // Reject contacts near the trackpad edge that are larger than a normal fingertip.
        // A wrist resting at the bottom edge while scrolling is a common false-positive source.
        let pos = finger.normalized.position
        let nearEdge = pos.x < edgeProximityZone || pos.x > (1 - edgeProximityZone)
                    || pos.y < edgeProximityZone || pos.y > (1 - edgeProximityZone)
        if nearEdge && finger.size > edgePalmSizeThreshold { return false }
        return true
    }

    // MARK: - Three-finger tap / click

    private func processThreeFinger(fingers: [MTFinger], timestamp: Double) {
        let count = fingers.count
        if count >= 3 {
            // Scroll guard: if 2 or more contacts are moving at scroll speed, the user is
            // doing a 2-finger scroll and the extra contact is an incidental palm — abort.
            let scrolling = fingers.filter { f in
                let v = f.normalized.velocity
                return (v.x * v.x + v.y * v.y).squareRoot() > scrollVelocityThreshold
            }.count
            if scrolling >= 2 {
                // Disarm any in-progress gesture; the palm-while-scrolling scenario
                // should never emit a tap or click.
                threeFingerStart = nil
                tapFired = false
                return
            }

            // Don't re-arm within the cooldown window — prevents double-fire when
            // fingers briefly re-register during the lift phase.
            let sinceLastTap = timestamp - lastTapTimestamp
            if threeFingerStart == nil && sinceLastTap > tapCooldown {
                threeFingerStart = timestamp
                tapFired = false
            }
            // Check for click threshold crossing: emit threeFingerClick once when
            // 3 fingers have been held for >= clickMinDuration. Setting tapFired
            // prevents a threeFingerTap from also firing when fingers lift.
            if let start = threeFingerStart, !tapFired {
                let duration = timestamp - start
                if duration >= clickMinDuration {
                    emit(.threeFingerClick)
                    tapFired = true
                    lastTapTimestamp = timestamp
                }
            }
        } else {
            // Fingers dropped below 3 — evaluate and always reset.
            // Do NOT wait for count==0: the callback filters out zero-count frames,
            // so that frame never arrives and the state machine would stay stuck.
            if let start = threeFingerStart {
                let duration = timestamp - start
                if !tapFired && duration < tapMaxDuration {
                    emit(.threeFingerTap)
                    lastTapTimestamp = timestamp
                }
                threeFingerStart = nil
                tapFired = false
            }
        }
    }

    // MARK: - Force click corner

    private func processForceClick(fingers: [MTFinger]) {
        // Clean up tracking for fingers no longer present
        let activeIDs = Set(fingers.map { $0.identifier })
        forceClickFired = forceClickFired.intersection(activeIDs)

        for finger in fingers {
            guard !forceClickFired.contains(finger.identifier) else { continue }

            // Skip if the finger is moving (dragging).
            let vel = finger.normalized.velocity
            let speed = (vel.x * vel.x + vel.y * vel.y).squareRoot()
            guard speed < dragVelocityThreshold else { continue }

            let pos = finger.normalized.position
            guard let corner = detectCorner(x: pos.x, y: pos.y) else { continue }

            // Pre-arm the click suppressor as soon as pressure clears normal-touch
            // range. This beats the OS leftMouseDown which fires at ~the same level
            // as our gesture threshold. The suppressor safely disarms after 300ms
            // if no click follows.
            if finger.zTotal >= forcePreArmThreshold {
                ClickSuppressor.shared.arm()
            }

            // Fire the gesture once pressure crosses the confirmed force threshold.
            if finger.zTotal >= forceThreshold {
                emit(.forceClickCorner(corner))
                forceClickFired.insert(finger.identifier)
            }
        }
    }

    private func detectCorner(x: Float, y: Float) -> Corner? {
        let z = cornerZoneSize
        let inLeft   = x < z
        let inRight  = x > (1 - z)
        let inTop    = y > (1 - z)
        let inBottom = y < z

        if inLeft  && inTop    { return .topLeft }
        if inRight && inTop    { return .topRight }
        if inLeft  && inBottom { return .bottomLeft }
        if inRight && inBottom { return .bottomRight }
        return nil
    }

    // MARK: - Emit

    private func emit(_ gesture: GestureEvent) {
        print("[MacShortcuts] Gesture detected: \(gesture)")
        delegate?.didRecognize(gesture: gesture)
    }
}
