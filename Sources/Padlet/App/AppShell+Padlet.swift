// App/AppShell+Padlet.swift
// Padlet's values for the shared app shell (Vendor/app-shell): who it is, where its releases are,
// and where its update settings live (Preferences.general — the keys stay as they were).

import AboutKit
import AppKit
import AppShellCore
import Combine
import UpdaterKit

extension AppIdentity {
    static let padlet = AppIdentity(
        name: "Padlet",
        tagline: "Trackpad edge controls and extra gestures for your Mac.",
        repo: "vuhpquang/padlet",
        firstYear: 2026,
        accent: Theme.accent,
        whatsNew: .menuItem
    )
}

/// Update settings stored in `Preferences.general` (`autoCheckUpdates`, `autoInstallUpdates`).
@MainActor
final class PadletUpdateSettings: UpdateSettingsStore {
    private let prefs: Preferences
    init(prefs: Preferences) { self.prefs = prefs }

    var autoCheck: Bool {
        get { prefs.general.autoCheckUpdates }
        set { prefs.general.autoCheckUpdates = newValue }
    }

    var autoInstall: Bool {
        get { prefs.general.autoInstallUpdates }
        set { prefs.general.autoInstallUpdates = newValue }
    }

    var changes: AnyPublisher<Void, Never> {
        prefs.$general
            .map { [$0.autoCheckUpdates, $0.autoInstallUpdates] }
            .removeDuplicates()
            .dropFirst()
            .map { _ in () }
            .eraseToAnyPublisher()
    }
}

extension Updater {
    /// Padlet's one updater (GitHub release `vX.Y.Z` with `Padlet.dmg`).
    @MainActor static let shared = Updater(app: .padlet, matcher: .dmg, settings: PadletUpdateSettings(prefs: .shared))
}

extension WhatsNewTracker {
    /// "What's New in X" in Padlet's menus once after an update (menu bar app: no window opens by itself).
    @MainActor static let shared = WhatsNewTracker(app: .padlet)
}
