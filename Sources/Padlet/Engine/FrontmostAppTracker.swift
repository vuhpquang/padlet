// Engine/FrontmostAppTracker.swift
// Remembers the last app that was frontmost other than Padlet itself — opening the
// panel activates Padlet, but "Add <app>" should mean the app you were just using.

import AppKit
import Combine

final class FrontmostAppTracker: ObservableObject {

    static let shared = FrontmostAppTracker()

    @Published private(set) var lastExternalApp: AppInfo?

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
    }
}
