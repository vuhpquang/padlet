// UI/PanelSnapshot.swift
// DEBUG-only: render the menu bar panel to PNG files and quit, for visual review.
//   MACSHORTCUTS_SNAPSHOT=/some/dir .build/debug/MacShortcuts

#if DEBUG
import AppKit
import SwiftUI

enum PanelSnapshot {
    static func runIfRequested() {
        if ProcessInfo.processInfo.environment["MACSHORTCUTS_UPDATE_DRYRUN"] != nil {
            UpdateManager.shared.debugDryRun { result in
                print("update dry-run: \(result)")
                exit(0)
            }
            return
        }
        guard let dir = ProcessInfo.processInfo.environment["MACSHORTCUTS_SNAPSHOT"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                for (pageName, page) in [("main", SettingsView.Page.main), ("settings", .settings)] {
                    render(SettingsView(page: page), appearance: appearance,
                           to: URL(fileURLWithPath: dir).appendingPathComponent("panel-\(pageName)-\(name).png"))
                }
            }
            exit(0)
        }
    }

    private static func render<V: View>(_ view: V, appearance: NSAppearance.Name, to url: URL) {
        let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        hosting.appearance = NSAppearance(named: appearance)
        let size = hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = appearance == .darkAqua ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.95, alpha: 1)
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))   // let live values load
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("snapshot: \(url.path) \(Int(size.width))×\(Int(size.height))")
    }
}
#endif
