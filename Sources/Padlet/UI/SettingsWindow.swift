// UI/SettingsWindow.swift
// The Settings window — Padlet's own pages in the shared app-shell Settings shell (sidebar, then the
// shared Updates and About panes) — and the window plumbing that gives Padlet a Dock icon and an
// app menu while it is open. The menu bar panel stays the quick surface; both write to Preferences.shared.

import AboutKit
import AppKit
import AppShellCore
import Combine
import SettingsKit
import SwiftUI
import UpdaterKit

// MARK: - Panes

/// Raw values are pane ids. `updates` and `about` are drawn by SettingsShell.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, edges, gestures, profiles, updates, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .edges: return "Edge Controls"
        case .gestures: return "Gestures"
        case .profiles: return "App Profiles"
        case .updates: return "Updates"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .edges: return "rectangle.lefthalf.inset.filled"
        case .gestures: return "hand.raised.fingers.spread"
        case .profiles: return "square.stack.3d.up"
        case .updates: return "arrow.down.circle"
        case .about: return "info.circle"
        }
    }

    /// Padlet's own pages, in sidebar order.
    static let own: [SettingsPane] = [.general, .edges, .gestures, .profiles]
}

final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()
    @Published var pane: SettingsPane = .general
    @Published var profile: UUID?
}

// MARK: - Settings view

struct SettingsView: View {
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var router = SettingsRouter.shared
    @StateObject private var live = LiveStatus()

    var body: some View {
        SettingsShell(
            app: .padlet,
            updater: .shared,
            panes: SettingsPane.own.map { pane in
                SettingsKit.SettingsPane(id: pane.rawValue, title: pane.title, systemImage: pane.symbol) { page(pane) }
            },
            selection: Binding(get: { router.pane.rawValue },
                               set: { router.profile = nil; router.pane = SettingsPane(rawValue: $0) ?? .general }),
            style: SettingsShellStyle(sidebarIconTint: Theme.accent, windowSize: CGSize(width: 760, height: 580)),
            onWhatsNew: { AppWindows.shared.showWhatsNew() }
        )
        .tint(Theme.accent)
        .onAppear { live.start() }
        .onDisappear { live.stop() }
    }

    /// Padlet's pages are stock grouped forms (UI/SettingsPages.swift).
    @ViewBuilder
    private func page(_ pane: SettingsPane) -> some View {
        switch pane {
        case .general: GeneralSettingsPage(prefs: prefs, live: live)
        case .edges: EdgeSettingsPage(prefs: prefs, live: live)
        case .gestures: GestureSettingsPage(prefs: prefs)
        case .profiles:
            if let id = router.profile {
                ProfileDetailSettingsPage(prefs: prefs, profileID: id) { router.profile = nil }
            } else {
                ProfilesSettingsPage(prefs: prefs) { router.profile = $0 }
            }
        case .updates, .about: EmptyView()   // drawn by SettingsShell
        }
    }
}

// MARK: - Windows

/// Owns the Settings window (About is one of its panes). While any Padlet window is open the app becomes a
/// regular app (Dock icon + "Padlet" menu); when the last one closes it goes back to the
/// menu bar only.
final class AppWindows: NSObject, NSWindowDelegate {

    static let shared = AppWindows()

    private var settingsWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    private override init() {
        super.init()
        SettingsRouter.shared.$pane
            .sink { [weak self] pane in self?.settingsWindow?.title = pane.title }
            .store(in: &cancellables)
    }

    func showSettings(_ pane: SettingsPane? = nil) {
        if let pane { SettingsRouter.shared.pane = pane; SettingsRouter.shared.profile = nil }
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 750, height: 580),
                             styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = SettingsRouter.shared.pane.title
            let hosting = NSHostingView(rootView: SettingsView())
            w.contentView = hosting
            w.setContentSize(hosting.fittingSize)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.setFrameAutosaveName("PadletSettings")
            if !w.setFrameUsingName("PadletSettings") { w.center() }
            settingsWindow = w
        }
        present(settingsWindow)
    }

    /// About lives in the Settings window (shared About pane).
    func showAbout() { showSettings(.about) }

    /// Check now and show the Updates pane.
    func checkForUpdates() {
        MainActor.assumeIsolated { Updater.shared.check(userInitiated: true) }
        showSettings(.updates)
    }

    /// Release notes of the running version; clears the "What's New in X" menu item.
    func showWhatsNew() {
        MainActor.assumeIsolated {
            let app = AppIdentity.padlet
            WhatsNewWindow.show(app: app, version: app.version, tracker: .shared)
        }
    }

    private func present(_ window: NSWindow?) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        DispatchQueue.main.async {
            if self.settingsWindow !== closing || closing == nil { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

// MARK: - App menu

/// The menu bar shown while a Padlet window is in front (Padlet / Edit / Window).
enum AppMenu {
    static func install(target: AnyObject) {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let app = NSMenu(title: "Padlet")
        app.addItem(item("About Padlet", #selector(AppDelegate.showAbout(_:)), target: target))
        app.addItem(item("Check for Updates\u{2026}", #selector(AppDelegate.checkForUpdates(_:)), target: target))
        app.addItem(item("What's New", #selector(AppDelegate.showWhatsNew(_:)), target: target))
        app.addItem(.separator())
        app.addItem(item("Settings\u{2026}", #selector(AppDelegate.showSettings(_:)), key: ",", target: target))
        app.addItem(item("Welcome Guide\u{2026}", #selector(AppDelegate.showWelcome(_:)), target: target))
        app.addItem(.separator())
        app.addItem(item("Hide Padlet", #selector(NSApplication.hide(_:)), key: "h"))
        let hideOthers = item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), key: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        app.addItem(hideOthers)
        app.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        app.addItem(.separator())
        app.addItem(item("Quit Padlet", #selector(NSApplication.terminate(_:)), key: "q"))
        appItem.submenu = app
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(item("Undo", Selector(("undo:")), key: "z"))
        let redo = item("Redo", Selector(("redo:")), key: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(item("Cut", #selector(NSText.cut(_:)), key: "x"))
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), key: "c"))
        edit.addItem(item("Paste", #selector(NSText.paste(_:)), key: "v"))
        edit.addItem(item("Select All", #selector(NSText.selectAll(_:)), key: "a"))
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        window.addItem(item("Close", #selector(NSWindow.performClose(_:)), key: "w"))
        windowItem.submenu = window
        main.addItem(windowItem)
        NSApp.windowsMenu = window

        NSApp.mainMenu = main
    }

    private static func item(_ title: String, _ action: Selector, key: String = "",
                             target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }
}
