// App/PermissionsManager.swift
// Accessibility permission: check, prompt, and wait for the grant.

import AppKit
import ApplicationServices

final class PermissionsManager {

    private var timer: Timer?

    static func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system "would like to control this computer" prompt.
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Polls once a second (main thread) and calls `completion` once access is granted.
    func pollUntilGranted(completion: @escaping () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.timer = nil
            completion()
        }
    }
}
