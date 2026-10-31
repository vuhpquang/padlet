// Actions/ActionExecutor.swift
// Performs a GestureAction by synthesizing mouse / keyboard events (CGEvent) or
// launching an app. Needs Accessibility permission. Main thread.

import AppKit
import CoreGraphics
import Foundation

final class ActionExecutor {

    static let shared = ActionExecutor()

    private init() {}

    func execute(_ action: GestureAction) {
        switch action {
        case .none:
            break
        case .middleClick:
            middleClick()
        case .missionControl:
            postKey(126, flags: .maskControl)            // ⌃↑
        case .appExpose:
            postKey(125, flags: .maskControl)            // ⌃↓
        case .showDesktop:
            postKey(103)                                 // F11
        case .previousSpace:
            postKey(123, flags: .maskControl)            // ⌃←
        case .nextSpace:
            postKey(124, flags: .maskControl)            // ⌃→
        case .previousTab:
            postKey(48, flags: [.maskControl, .maskShift])   // ⌃⇧⇥
        case .nextTab:
            postKey(48, flags: .maskControl)             // ⌃⇥
        case .keystroke(let key, let modifiers):
            keystroke(key: key, modifiers: modifiers)
        case .openApp(let bundleID):
            openApp(bundleID: bundleID)
        }
    }

    // MARK: - Primitives

    /// Posts a key-down/key-up pair for a virtual key code.
    func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    private func middleClick() {
        // CGEvent uses a top-left origin; NSEvent.mouseLocation is bottom-left.
        let location = NSEvent.mouseLocation
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let point = CGPoint(x: location.x, y: screenHeight - location.y)
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.otherMouseDown, .otherMouseUp] {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .center)?
                .post(tap: .cghidEventTap)
        }
    }

    private func keystroke(key: String, modifiers: NSEvent.ModifierFlags) {
        guard var scalar = key.utf16.first else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.shift)   { flags.insert(.maskShift) }
        if modifiers.contains(.option)  { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
            event?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &scalar)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    private func openApp(bundleID: String) {
        guard !bundleID.isEmpty else { return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            Log.error("ActionExecutor: no app for bundle ID \(bundleID)")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error = error { Log.error("ActionExecutor: could not open \(bundleID): \(error)") }
        }
    }
}
