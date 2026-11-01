// UI/PanelSnapshot.swift
// DEBUG-only developer hooks, driven by environment variables:
//   PADLET_SNAPSHOT=/dir       render every screen (light + dark) to PNGs and quit
//   PADLET_UPDATE_DRYRUN=1     check → download → verify → stage an update, no install

#if DEBUG
import AppKit
import SwiftUI

enum PanelSnapshot {

    /// Returns true when a hook ran (the app should not continue launching).
    static func runIfRequested() -> Bool {
        let env = ProcessInfo.processInfo.environment
        if env["PADLET_UPDATE_DRYRUN"] != nil {
            UpdateManager.shared.debugDryRun { result in
                print("update dry-run: \(result)")
                exit(0)
            }
            return true
        }
        guard let dir = env["PADLET_SNAPSHOT"] else { return false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            renderAll(into: URL(fileURLWithPath: dir))
            exit(0)
        }
        return true
    }

    private static func renderAll(into dir: URL) {
        let prefs = Preferences.shared
        let sample = AppProfile(bundleID: "com.apple.Safari", name: "Safari", overrides: [
            GestureSlot.threeFingerTap.rawValue: .nextTab,
            GestureSlot.topEdgeSwipeLeft.rawValue: .previousTab,
            GestureSlot.cornerTopRight.rawValue: .builtin(.moveToNextDisplay),
            GestureSlot.cornerBottomLeft.rawValue: .pasteText(text: "Thanks for the review!"),
            GestureSlot.cornerBottomRight.rawValue: .builtin(.toggleDoNotDisturb),
            GestureSlot.threeFingerClick.rawValue: .runCommand(command: "open -a Notes"),
            GestureSlot.fourFingerTap.rawValue: .keystroke(key: "t", modifiers: [.command, .shift]),
        ])
        let savedProfiles = prefs.profiles
        prefs.profiles = [sample]
        defer { prefs.profiles = savedProfiles }

        for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let pages: [(String, PanelPage)] = [("main", .main), ("settings", .settings),
                                                ("profiles", .profiles), ("profile", .profile(sample.id))]
            for (name, page) in pages {
                PanelRouter.shared.page = page
                render(PanelView(maxContentHeight: 2000), appearance: appearance,
                       to: dir.appendingPathComponent("panel-\(name)-\(mode).png"))
            }
            for step in 0..<3 {
                render(OnboardingView(finish: {}, step: step), appearance: appearance,
                       to: dir.appendingPathComponent("onboarding-\(step)-\(mode).png"))
            }
            render(QuickMenuView(), appearance: appearance,
                   to: dir.appendingPathComponent("quickmenu-\(mode).png"))
            for pane in SettingsPane.allCases {
                SettingsRouter.shared.pane = pane
                SettingsRouter.shared.profile = nil
                render(SettingsView(), appearance: appearance,
                       to: dir.appendingPathComponent("settings-\(pane.rawValue)-\(mode).png"))
            }
            SettingsRouter.shared.pane = .profiles
            SettingsRouter.shared.profile = sample.id
            render(SettingsView(), appearance: appearance,
                   to: dir.appendingPathComponent("settings-profile-\(mode).png"))
        }
        SettingsRouter.shared.pane = .general
        SettingsRouter.shared.profile = nil
        PanelRouter.shared.page = .main
    }

    private static func render<V: View>(_ view: V, appearance: NSAppearance.Name, to url: URL) {
        let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        hosting.appearance = NSAppearance(named: appearance)
        let size = hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("snapshot: \(url.lastPathComponent) \(Int(size.width))×\(Int(size.height))")
    }
}
#endif
