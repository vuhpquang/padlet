// UI/PanelSnapshot.swift
// DEBUG-only developer hooks, driven by environment variables:
//   PADLET_SNAPSHOT=/dir       render every screen (light + dark) to PNGs and quit
//   PADLET_SWITCHER_DEMO=/dir  show the live app switcher (glass) light + dark, capture it, quit
//   PADLET_UPDATE_DRYRUN=1     check → download → verify → stage an update, no install

#if DEBUG
import AppShellCore
import UpdaterKit
import AppKit
import SwiftUI

enum PanelSnapshot {

    /// Returns true when a hook ran (the app should not continue launching).
    static func runIfRequested() -> Bool {
        let env = ProcessInfo.processInfo.environment
        if env["PADLET_UPDATE_DRYRUN"] != nil {
            Task { @MainActor in
                print("update dry-run: \(await Updater.shared.dryRun())")
                exit(0)
            }
            return true
        }
        if let dir = env["PADLET_SWITCHER_DEMO"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { switcherDemo(into: URL(fileURLWithPath: dir)) }
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
        renderSwitcher(into: dir)
    }

    /// Shows the real switcher panel and captures its window with `screencapture -l`.
    private static func switcherDemo(into dir: URL) {
        for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            AppSwitcher.shared.begin()
            AppSwitcher.shared.select(offset: 1)
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            if let id = AppSwitcher.shared.windowNumber {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                task.arguments = ["-x", "-o", "-l\(id)", dir.appendingPathComponent("switcher-live-\(mode).png").path]
                try? task.run()
                task.waitUntilExit()
            }
            AppSwitcher.shared.end(commit: false)
        }
        exit(0)
    }

    /// The app switcher over a light and a dark backdrop, like a wallpaper behind glass.
    private static func renderSwitcher(into dir: URL) {
        let model = AppSwitcherModel()
        let names = ["Finder", "Mail", "Notes", "Safari", "Music", "Utilities/Terminal"]
        model.items = names.enumerated().map { i, name in
            let path = name == "Finder" ? "/System/Library/CoreServices/Finder.app"
                : name == "Safari" ? "/Applications/Safari.app" : "/System/Applications/\(name).app"
            return SwitcherItem(id: pid_t(i), name: (name as NSString).lastPathComponent,
                                icon: NSWorkspace.shared.icon(forFile: URL(fileURLWithPath: path).resolvingSymlinksInPath().path))
        }
        model.selected = names.count - 1
        for (mode, appearance, backdrop) in [("light", NSAppearance.Name.aqua, Color(white: 0.92)),
                                             ("dark", .darkAqua, Color(white: 0.12))] {
            render(AppSwitcherView(model: model, background: .blur).padding(40).background(backdrop), appearance: appearance,
                   to: dir.appendingPathComponent("switcher-\(mode).png"))
        }
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
