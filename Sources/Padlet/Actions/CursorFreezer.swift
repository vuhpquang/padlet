// Core/CursorFreezer.swift
// Keeps the pointer still while a finger slides along a trackpad edge, so turning the
// volume up doesn't also drag the cursor across the screen.
//
// Two layers, because a background app can't fully own the cursor:
//   1. CGAssociateMouseAndMouseCursorPosition(false) detaches the cursor from the mouse.
//   2. A HID-level event tap swallows mouseMoved/drag events while frozen and warps the
//      pointer back to its anchor, catching whatever layer 1 lets through.
// The warp suppression interval is set to 0 so the warp doesn't briefly lock input.

import CoreGraphics
import Foundation

final class CursorFreezer {

    static let shared = CursorFreezer()

    private let lock = NSLock()
    private var _anchor: CGPoint?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Where the pointer is pinned, or nil when not frozen.
    private var anchor: CGPoint? {
        get { lock.lock(); defer { lock.unlock() }; return _anchor }
        set { lock.lock(); defer { lock.unlock() }; _anchor = newValue }
    }

    var isFrozen: Bool { anchor != nil }

    private init() {
        CGEventSource(stateID: .combinedSessionState)?.localEventsSuppressionInterval = 0
        install()
    }

    // MARK: - Public API (main thread)

    /// The pointer's current position in global top-left-origin coordinates.
    static func currentLocation() -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    /// Pins the pointer at `point` (typically where it was when the finger touched down,
    /// which also undoes the small drift before the slide was recognised).
    func freeze(at point: CGPoint) {
        anchor = point
        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(0)
    }

    func release() {
        guard anchor != nil else { return }
        anchor = nil
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    /// Re-create the event tap — macOS disables taps across sleep.
    func reinstall() {
        release()
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        install()
    }

    // MARK: - Event tap

    private func install() {
        let mask: CGEventMask = (1 << CGEventType.mouseMoved.rawValue)
                              | (1 << CGEventType.leftMouseDragged.rawValue)
                              | (1 << CGEventType.rightMouseDragged.rawValue)
                              | (1 << CGEventType.otherMouseDragged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let freezer = Unmanaged<CursorFreezer>.fromOpaque(refcon).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = freezer.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                guard let anchor = freezer.anchor else { return Unmanaged.passUnretained(event) }
                CGWarpMouseCursorPosition(anchor)
                return nil
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.info("CursorFreezer: could not create event tap (Accessibility permission required).")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
    }
}
