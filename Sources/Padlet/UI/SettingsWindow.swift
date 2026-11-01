// UI/SettingsWindow.swift
// The full Settings window (sidebar + pane), the About window, and the window plumbing
// that gives Padlet a Dock icon and an app menu while one of its windows is open.
// The menu bar panel stays the quick surface; both write to Preferences.shared.

import AppKit
import Combine
import SwiftUI

// MARK: - Panes

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, edges, gestures, profiles, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .edges: return "Edge Controls"
        case .gestures: return "Gestures"
        case .profiles: return "App Profiles"
        case .about: return "About & Updates"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .edges: return "rectangle.lefthalf.inset.filled"
        case .gestures: return "hand.raised.fingers.spread.fill"
        case .profiles: return "square.stack.3d.up.fill"
        case .about: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: return .gray
        case .edges: return Color(red: 0.19, green: 0.65, blue: 1.0)
        case .gestures: return Theme.accent
        case .profiles: return Color(red: 1.0, green: 0.55, blue: 0.1)
        case .about: return Color(red: 0.55, green: 0.45, blue: 1.0)
        }
    }
}

final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()
    @Published var pane: SettingsPane = .general
    @Published var profile: UUID?
}

// MARK: - Settings view

struct SettingsView: View {
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var updates = UpdateManager.shared
    @ObservedObject private var router = SettingsRouter.shared
    @StateObject private var live = LiveStatus()

    static let contentWidth: CGFloat = 470

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView(.vertical) {
                pane
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
                    .frame(width: Self.contentWidth + 56, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 580)
        .tint(Theme.accent)
        .onAppear { live.start() }
        .onDisappear { live.stop() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(nsImage: padletIcon).resizable().frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Padlet").font(.system(size: 14, weight: .semibold))
                    Text("Version \(updates.currentVersion)").font(.system(size: 10.5)).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 12)

            ForEach(SettingsPane.allCases) { pane in
                if pane == .about { Spacer().frame(height: 10) }
                Button {
                    router.profile = nil
                    router.pane = pane
                } label: {
                    HStack(spacing: 9) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(pane.color.gradient)
                            Image(systemName: pane.symbol)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .frame(width: 22, height: 22)
                        Text(pane.title).font(.system(size: 13))
                        Spacer()
                        if pane == .about, case .available = updates.state {
                            Circle().fill(Color.red).frame(width: 7, height: 7)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(router.pane == pane ? Color.primary.opacity(0.10) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(width: 196)
        .background(Color.primary.opacity(0.035))
    }

    @ViewBuilder
    private var pane: some View {
        VStack(alignment: .leading, spacing: 16) {
            paneHeader
            switch router.pane {
            case .general: generalPane
            case .edges: edgesPane
            case .gestures: gesturesPane
            case .profiles: profilesPane
            case .about:
                VStack(alignment: .leading, spacing: 18) {
                    AboutView(updates: updates)
                    Divider()
                    UpdatesSection(prefs: prefs, updates: updates, showsStatus: false)
                }
            }
        }
    }

    @ViewBuilder
    private var paneHeader: some View {
        if router.pane != .about {
            HStack(spacing: 8) {
                if router.pane == .profiles, router.profile != nil {
                    Button { router.profile = nil } label: {
                        Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help("All profiles")
                }
                Text(router.pane.title)
                    .font(.system(size: 20, weight: .bold))
            }
        }
    }

    // MARK: Panes

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card(padding: 12) {
                SettingRow(icon: "power", title: "Padlet",
                           subtitle: prefs.flags.masterEnabled ? "Gestures and edge controls are on"
                                                               : "Everything is off",
                           active: prefs.flags.masterEnabled) {
                    HStack(spacing: 10) {
                        StatusPill(enabled: prefs.flags.masterEnabled, granted: live.accessibilityGranted)
                        SwitchToggle(isOn: $prefs.flags.masterEnabled)
                    }
                }
            }
            if !live.accessibilityGranted {
                Card(padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        SettingRow(icon: "exclamationmark.triangle.fill", title: "Accessibility access needed",
                                   subtitle: "Padlet can't see the trackpad until you allow it",
                                   active: true, color: .orange) {
                            Button("Open Settings") { openAccessibilitySettings() }.controlSize(.small)
                        }
                        HStack(spacing: 6) {
                            Text("Padlet is already switched on there but still asks?")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Button("Reset & Ask Again") { PermissionsManager().resetAndRequest() }
                                .buttonStyle(.link)
                                .font(.system(size: 11))
                        }
                        .padding(.leading, 40)
                    }
                }
            }
            GeneralSection(prefs: prefs, live: live, showsHeader: false)
        }
    }

    private var edgesPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            LevelsCard(live: live, left: prefs.edge.leftFunction, right: prefs.edge.rightFunction)
                .opacity(prefs.flags.edgeControls ? 1 : 0.5)
            EdgeControlsSection(prefs: prefs)
            Divider()
            EdgeBehaviorSection(prefs: prefs)
        }
        .disabled(!prefs.flags.masterEnabled)
    }

    private var gesturesPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Expand a gesture to choose what each variant does. Window actions work on the front window of the app you're using.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            GesturesSection(prefs: prefs, startExpanded: true, pickerWidth: 230, showsHeader: false)
        }
        .disabled(!prefs.flags.masterEnabled)
    }

    @ViewBuilder
    private var profilesPane: some View {
        if let id = router.profile {
            ProfileDetailPage(prefs: prefs, profileID: id, pickerWidth: 230) { router.profile = nil }
        } else {
            ProfilesPage(prefs: prefs) { router.profile = $0 }
        }
    }
}

// MARK: - About

enum Author {
    static let name = "Ha Phung Quang Vu"
    static let github = URL(string: "https://github.com/vuhpquang")!
    static let linkedIn = URL(string: "https://www.linkedin.com/in/vuhpquang")!
}

struct AboutView: View {
    @ObservedObject var updates: UpdateManager

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: padletIcon)
                .resizable()
                .frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
            VStack(spacing: 4) {
                Text("Padlet").font(.system(size: 26, weight: .bold))
                Text("Version \(updates.currentVersion) (\(buildNumber))")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
            Text("Trackpad edge controls and extra gestures for your Mac.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 2) {
                Text("Made by").font(.system(size: 11)).foregroundColor(.secondary)
                Text(Author.name).font(.system(size: 15, weight: .semibold))
                HStack(spacing: 12) {
                    Link("GitHub", destination: Author.github)
                    Text("·").foregroundColor(.secondary)
                    Link("LinkedIn", destination: Author.linkedIn)
                    Text("·").foregroundColor(.secondary)
                    Link("Source code", destination: URL(string: "https://github.com/\(UpdateManager.repo)")!)
                }
                .font(.system(size: 12))
                .padding(.top, 2)
            }
            .padding(.vertical, 4)

            Card(padding: 12) {
                HStack(spacing: 10) {
                    IconBadge(symbol: statusSymbol, active: true, color: statusColor)
                    Text(statusText)
                        .font(.system(size: 12.5))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    switch updates.state {
                    case .available:
                        Button("Install Update") { updates.install() }.buttonStyle(.borderedProminent)
                    case .checking, .downloading, .installing:
                        ProgressView().controlSize(.small)
                    default:
                        Button("Check for Updates") { updates.check(userInitiated: true) }
                    }
                }
                .controlSize(.small)
            }
            .frame(maxWidth: 400)

            Text("© \(String(Calendar.current.component(.year, from: Date()))) \(Author.name)")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
    }

    private var statusText: String {
        switch updates.state {
        case .idle: return "Padlet checks for updates automatically."
        case .checking: return "Checking for updates\u{2026}"
        case .upToDate: return "Padlet is up to date."
        case .available(let v): return "Padlet \(v) is available."
        case .downloading: return "Downloading the update\u{2026}"
        case .installing: return "Installing — Padlet will relaunch."
        case .failed(let message): return "Couldn't update: \(message)"
        }
    }

    private var statusSymbol: String {
        switch updates.state {
        case .upToDate: return "checkmark"
        case .available: return "arrow.down"
        case .failed: return "exclamationmark"
        default: return "arrow.triangle.2.circlepath"
        }
    }

    private var statusColor: Color {
        switch updates.state {
        case .upToDate: return .green
        case .available: return Theme.accent
        case .failed: return .orange
        default: return .gray
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

    /// About lives in the Settings window (About & Updates pane).
    func showAbout() { showSettings(.about) }

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
