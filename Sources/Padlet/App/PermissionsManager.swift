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

    /// Clears Padlet's entries in Privacy & Security, then asks again. Fixes a grant that
    /// was made for a differently signed build: it still shows as on, but macOS ignores it
    /// and won't let you remove it.
    func resetAndRequest() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            for service in ["Accessibility", "PostEvent"] {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                task.arguments = ["reset", service, bundleID]
                task.standardOutput = FileHandle.nullDevice
                task.standardError = FileHandle.nullDevice
                try? task.run()
                task.waitUntilExit()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.requestAccessibilityPermission()
                openAccessibilitySettings()
            }
        }
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
