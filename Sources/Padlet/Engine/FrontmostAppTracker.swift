// Engine/FrontmostAppTracker.swift
// Remembers the last app that was frontmost other than Padlet itself — opening the
// panel activates Padlet, but "Add <app>" should mean the app you were just using.

import AppKit
import Combine

final class FrontmostAppTracker: ObservableObject {

    static let shared = FrontmostAppTracker()

    @Published private(set) var lastExternalApp: AppInfo?

    /// Recently active regular apps, most recent first (Padlet excluded).
    private var recent: [NSRunningApplication] = []

    private var cancellable: AnyCancellable?

    private init() {
        record(NSWorkspace.shared.frontmostApplication)
        cancellable = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] note in
                self?.record(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
            }
    }

    private func record(_ app: NSRunningApplication?) {
        guard let app = app, let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier,
              app.activationPolicy == .regular else { return }
        lastExternalApp = AppInfo(bundleID: id, name: app.localizedName)
        recent.removeAll { $0.processIdentifier == app.processIdentifier || $0.isTerminated }
        recent.insert(app, at: 0)
        if recent.count > 32 { recent.removeLast(recent.count - 32) }
    }

    /// Apps for the top-edge switcher: the frontmost first, then most recently used,
    /// then the other running Dock apps (Padlet excluded).
    func switcherApps() -> [NSRunningApplication] {
        let me = Bundle.main.bundleIdentifier
        func eligible(_ app: NSRunningApplication) -> Bool {
            !app.isTerminated && app.activationPolicy == .regular && app.bundleIdentifier != me
        }
        recent.removeAll { $0.isTerminated }
        var result: [NSRunningApplication] = []
        var seen: Set<pid_t> = []
        let candidates = [NSWorkspace.shared.frontmostApplication].compactMap { $0 }
            + recent + NSWorkspace.shared.runningApplications
        for app in candidates where eligible(app) && !seen.contains(app.processIdentifier) {
            seen.insert(app.processIdentifier)
            result.append(app)
        }
        return result
    }

    /// Brings back the app that was in front before the current one (like a quick ⌘⇥).
    func activatePreviousApp() {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        recent.removeAll { $0.isTerminated }
        guard let target = recent.first(where: { $0.processIdentifier != front }) else { return }
        if #available(macOS 14.0, *) {
            target.activate()
        } else {
            target.activate(options: [.activateIgnoringOtherApps])
        }
    }
}
