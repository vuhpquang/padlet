// Core/CursorFreezer.swift
// Keeps the pointer still while a finger slides along a trackpad edge, so turning the
// volume up doesn't also drag the cursor across the screen.
//
// Two layers, because a background app can't fully own the cursor:
//   1. CGAssociateMouseAndMouseCursorPosition(false) detaches the cursor from the mouse.
//   2. A HID-level event tap swallows mouseMoved/drag events while frozen and warps the
//      pointer back to its anchor, catching whatever layer 1 lets through.
// The warp suppression interval is set to 0 so the warp doesn't briefly lock input.
//
// Layer 2 is what actually works (measured on macOS 27: tap + warp ≈ 1 px drift, layer 1
// alone does nothing). The cursor moves *before* the tap sees the event, so the warp-back
// must be immediate: the tap runs on its own thread, never the main thread, which is busy
// with volume/OSD/SwiftUI work exactly while the finger slides.

import CoreGraphics
import Foundation

final class CursorFreezer {

    static let shared = CursorFreezer()

    private let lock = NSLock()
    private var _anchor: CGPoint?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Run loop of the dedicated tap thread.
    private let tapRunLoop: CFRunLoop
    /// Moves swallowed and the largest distance seen, for the log line on release.
    private var heldMoves = 0
    private var maxDrift: CGFloat = 0

    /// Where the pointer is pinned, or nil when not frozen.
    private var anchor: CGPoint? {
        get { lock.lock(); defer { lock.unlock() }; return _anchor }
        set { lock.lock(); defer { lock.unlock() }; _anchor = newValue }
    }

    var isFrozen: Bool { anchor != nil }

    private init() {
        CGEventSource(stateID: .combinedSessionState)?.localEventsSuppressionInterval = 0
        tapRunLoop = Self.startTapThread()
        install()
    }

    /// A thread that only services the event tap.
    private static func startTapThread() -> CFRunLoop {
        var loop: CFRunLoop?
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            loop = CFRunLoopGetCurrent()
            // A run loop with no sources exits at once; keep it alive with a dummy port.
            let keepAlive = NSMachPort()
            RunLoop.current.add(keepAlive, forMode: .default)
            ready.signal()
            while true { RunLoop.current.run(mode: .default, before: .distantFuture) }
        }
        thread.name = "Padlet.CursorFreezer"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        return loop!
    }

    // MARK: - Public API (main thread)

    /// The pointer's current position in global top-left-origin coordinates.
    static func currentLocation() -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    /// Pins the pointer at `point` (typically where it was when the finger touched down,
    /// which also undoes the small drift before the slide was recognised).
    func freeze(at point: CGPoint) {
        lock.lock(); heldMoves = 0; maxDrift = 0; lock.unlock()
        anchor = point
        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(0)
    }

    func release() {
        guard anchor != nil else { return }
        anchor = nil
        CGAssociateMouseAndMouseCursorPosition(1)
        lock.lock(); let held = heldMoves; let drift = maxDrift; lock.unlock()
        Log.info("CursorFreezer: held \(held) moves, max drift \(Int(drift.rounded())) px")
    }

    /// Called on the tap thread for each swallowed move.
    fileprivate func hold(_ event: CGEvent, at anchor: CGPoint) {
        CGWarpMouseCursorPosition(anchor)
        let p = event.location
        lock.lock()
        heldMoves += 1
        maxDrift = max(maxDrift, hypot(p.x - anchor.x, p.y - anchor.y))
        lock.unlock()
    }

    /// Re-create the event tap — macOS disables taps across sleep.
    func reinstall() {
        release()
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(tapRunLoop, src, .commonModes) }
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
                freezer.hold(event, at: anchor)
                return nil
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.info("CursorFreezer: could not create event tap (Accessibility permission required).")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(tapRunLoop, source, .commonModes)
        CFRunLoopWakeUp(tapRunLoop)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
    }
}
