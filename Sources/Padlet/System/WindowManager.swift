// System/WindowManager.swift
// Moves and resizes the frontmost app's focused window through the Accessibility API
// (the same permission Padlet already needs). AX positions use a top-left origin on the
// primary display; NSScreen uses bottom-left — `axRect(_:)` converts.

import AppKit
import ApplicationServices

enum WindowManager {

    enum Placement { case fill, leftHalf, rightHalf, center }

    // MARK: - Actions

    /// Moves the window to the next (+1) or previous (−1) display, keeping its relative
    /// position and size. A window that filled its screen fills the new one.
    static func moveToDisplay(offset: Int) {
        guard let window = focusedWindow(), let frame = frame(of: window) else { return }
        let screens = orderedScreens()
        guard screens.count > 1, let current = screen(containing: frame, in: screens),
              let index = screens.firstIndex(of: current) else { return }
        let target = screens[(index + offset + screens.count) % screens.count]

        let from = axRect(current.visibleFrame)
        let to = axRect(target.visibleFrame)
        let filled = abs(frame.width - from.width) < 24 && abs(frame.height - from.height) < 24

        var new: CGRect
        if filled {
            new = to
        } else {
            let width = min(frame.width, to.width)
            let height = min(frame.height, to.height)
            let rx = from.width > frame.width ? (frame.minX - from.minX) / (from.width - frame.width) : 0
            let ry = from.height > frame.height ? (frame.minY - from.minY) / (from.height - frame.height) : 0
            new = CGRect(x: to.minX + max(0, min(1, rx)) * (to.width - width),
                         y: to.minY + max(0, min(1, ry)) * (to.height - height),
                         width: width, height: height)
        }
        setFrame(new, of: window)
    }

    static func place(_ placement: Placement) {
        guard let window = focusedWindow(), let frame = frame(of: window),
              let screen = screen(containing: frame, in: orderedScreens()) else { return }
        let area = axRect(screen.visibleFrame)
        let new: CGRect
        switch placement {
        case .fill:
            new = area
        case .leftHalf:
            new = CGRect(x: area.minX, y: area.minY, width: (area.width / 2).rounded(), height: area.height)
        case .rightHalf:
            let w = (area.width / 2).rounded()
            new = CGRect(x: area.maxX - w, y: area.minY, width: w, height: area.height)
        case .center:
            new = CGRect(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2,
                         width: min(frame.width, area.width), height: min(frame.height, area.height))
        }
        setFrame(new, of: window)
    }

    static func minimize() {
        guard let window = focusedWindow() else { return }
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
    }

    static func toggleFullScreen() {
        guard let window = focusedWindow() else { return }
        let attribute = "AXFullScreen" as CFString
        var value: CFTypeRef?
        let isFull = AXUIElementCopyAttributeValue(window, attribute, &value) == .success
            && (value as? Bool) == true
        AXUIElementSetAttributeValue(window, attribute, (!isFull) as CFBoolean)
    }

    static func close() {
        guard let window = focusedWindow() else { return }
        var button: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &button) == .success,
              let button, CFGetTypeID(button) == AXUIElementGetTypeID() else { return }
        AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)   // swiftlint:disable:this force_cast
    }

    // MARK: - AX plumbing

    private static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        return (window as! AXUIElement)   // swiftlint:disable:this force_cast
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        // swiftlint:disable force_cast
        AXValueGetValue(posRef as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        // swiftlint:enable force_cast
        return CGRect(origin: position, size: size)
    }

    private static func setFrame(_ rect: CGRect, of window: AXUIElement) {
        var position = rect.origin
        var size = rect.size
        guard let pos = AXValueCreate(.cgPoint, &position), let sz = AXValueCreate(.cgSize, &size) else { return }
        // Size, move, size again: apps clamp size to the screen they're currently on.
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sz)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pos)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sz)
    }

    // MARK: - Screens

    /// Left-to-right, then top-to-bottom — the order "next display" walks.
    static func orderedScreens() -> [NSScreen] {
        NSScreen.screens.sorted {
            $0.frame.minX != $1.frame.minX ? $0.frame.minX < $1.frame.minX : $0.frame.maxY > $1.frame.maxY
        }
    }

    /// The screen holding most of an AX-space rect.
    private static func screen(containing rect: CGRect, in screens: [NSScreen]) -> NSScreen? {
        screens.max { overlap(rect, axRect($0.frame)) < overlap(rect, axRect($1.frame)) }
            .flatMap { overlap(rect, axRect($0.frame)) > 0 ? $0 : nil }
            ?? screens.first { axRect($0.frame).contains(CGPoint(x: rect.midX, y: rect.midY)) }
            ?? NSScreen.main
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        return i.isNull ? 0 : i.width * i.height
    }

    /// Converts a Cocoa (bottom-left origin) rect to AX (top-left of the primary display).
    static func axRect(_ cocoa: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? cocoa.maxY
        return CGRect(x: cocoa.minX, y: primaryHeight - cocoa.maxY, width: cocoa.width, height: cocoa.height)
    }
}
