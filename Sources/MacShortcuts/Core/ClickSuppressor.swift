// Core/ClickSuppressor.swift
// Intercepts left-click events during force-click gestures so the trackpad's
// natural first-stage click doesn't leak through alongside our gesture action.
//
// How it works:
//   1. GestureRecognizer calls ClickSuppressor.shared.arm() the moment a
//      force-click corner gesture is detected.
//   2. This sets a flag valid for up to 300 ms.
//   3. A CGEventTap installed at the HID level intercepts leftMouseDown and
//      leftMouseUp events. While the flag is set it returns nil — consuming
//      both events — and then disarms itself.
//
// Requires Accessibility permission (same permission the rest of the app needs).

import CoreGraphics
import Foundation

final class ClickSuppressor {

    static let shared = ClickSuppressor()

    private let lock = NSLock()
    private var _armed = false
    private var disarmTimer: DispatchWorkItem?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var armed: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _armed }
        set { lock.lock(); defer { lock.unlock() }; _armed = newValue }
    }

    private init() {
        install()
    }

    // MARK: - Public API

    /// Arm the suppressor. The next leftMouseDown + leftMouseUp pair will be
    /// consumed (not forwarded to apps). Disarms automatically after 300 ms
    /// if no click arrives.
    func arm(for duration: TimeInterval = 0.3) {
        armed = true
        let item = DispatchWorkItem { [weak self] in self?.armed = false }
        // The timer is touched from the multitouch thread and the main thread.
        lock.lock()
        disarmTimer?.cancel()
        disarmTimer = item
        lock.unlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    /// Tear down the existing event tap and install a fresh one.
    /// Call this after the machine wakes from sleep — macOS disables CGEventTaps on sleep.
    func reinstall() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        install()
    }

    // MARK: - Private

    private func install() {
        let mask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue)
                              | (1 << CGEventType.leftMouseUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let self_ = Unmanaged<ClickSuppressor>.fromOpaque(refcon).takeUnretainedValue()
                guard self_.armed else { return Unmanaged.passRetained(event) }
                // Suppress this event; disarm after we see the up.
                if type == .leftMouseUp {
                    self_.armed = false
                    self_.disarmTimer?.cancel()
                }
                return nil
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[MacShortcuts] ClickSuppressor: could not create event tap (Accessibility permission required).")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        print("[MacShortcuts] ClickSuppressor: installed.")
    }

    deinit {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
    }
}
