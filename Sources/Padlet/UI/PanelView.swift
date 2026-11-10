// UI/PanelView.swift
// The menu bar panel (popover). Pages:
//   main        — status + master switch, live edge levels, edge controls, gestures
//   settings    — set-once options, appearance, login, updates
//   profiles    — per-app gesture overrides
//   profile(id) — one app's overrides
// Everything writes straight to Preferences.shared (persisted + applied immediately).

import AppKit
import SwiftUI

// MARK: - Routing

enum PanelPage: Equatable {
    case main, settings, profiles, profile(UUID)
}

final class PanelRouter: ObservableObject {
    static let shared = PanelRouter()
    @Published var page: PanelPage = .main

    func go(_ page: PanelPage) {
        withAnimation(.easeInOut(duration: 0.15)) { self.page = page }
    }
}

// MARK: - Live status (polled while the panel is open)

final class LiveStatus: ObservableObject {
    @Published var levels: [EdgeFunction: Float] = [:]
    @Published var muted = false
    @Published var accessibilityGranted = true
    @Published var launchAtLogin = LaunchAtLogin.isEnabled

    private var timer: Timer?

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        var l: [EdgeFunction: Float] = [:]
        l[.volume] = VolumeControl.get()
        l[.brightness] = BrightnessControl.get()
        if levels != l { levels = l }
        muted = VolumeControl.isMuted() ?? false
        accessibilityGranted = PermissionsManager.isAccessibilityGranted()
        launchAtLogin = LaunchAtLogin.isEnabled
    }
}

// MARK: - Root

struct PanelView: View {
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var updates = UpdateManager.shared
    @ObservedObject private var router = PanelRouter.shared
    @StateObject private var live = LiveStatus()

    var maxContentHeight: CGFloat = 600

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    switch router.page {
                    case .main: MainPage(prefs: prefs, live: live, updates: updates)
                    case .settings: SettingsPage(prefs: prefs, live: live, updates: updates)
                    case .profiles: ProfilesPage(prefs: prefs)
                    case .profile(let id): ProfileDetailPage(prefs: prefs, profileID: id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .frame(width: Theme.panelWidth)
            }
            .frame(maxHeight: maxContentHeight)
            .fixedSize(horizontal: false, vertical: true)
            Divider().padding(.horizontal, 14)
            footer
        }
        .frame(width: Theme.panelWidth)
        .tint(Theme.accent)
        .onAppear { live.start() }
        .onDisappear { live.stop() }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 9) {
            if router.page != .main {
                Button { router.go(backTarget) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Back")
            }
            Image(nsImage: padletIcon)
                .resizable()
                .frame(width: 24, height: 24)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            if router.page == .main {
                StatusPill(enabled: prefs.flags.masterEnabled, granted: live.accessibilityGranted)
                SwitchToggle(isOn: $prefs.flags.masterEnabled)
                    .help("Turn every gesture on or off")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var title: String {
        switch router.page {
        case .main: return "Padlet"
        case .settings: return "Settings"
        case .profiles: return "App Profiles"
        case .profile(let id): return prefs.profiles.first { $0.id == id }?.name ?? "Profile"
        }
    }

    private var backTarget: PanelPage {
        if case .profile = router.page { return .profiles }
        return .main
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 14) {
            if router.page == .main {
                Button { router.go(.settings) } label: { Label("Settings", systemImage: "gearshape") }
            } else {
                Text("Padlet \(updates.currentVersion)").foregroundColor(.secondary)
            }
            Spacer()
            Menu {
                Button("Settings Window\u{2026}") {
                    NotificationCenter.default.post(name: .padletShowSettingsWindow, object: nil)
                }
                Button("About Padlet") { NotificationCenter.default.post(name: .padletShowAbout, object: nil) }
                Button("Check for Updates\u{2026}") {
                    updates.check(userInitiated: true)
                    NotificationCenter.default.post(name: .padletShowAbout, object: nil)
                }
                Button("Welcome Guide\u{2026}") { NotificationCenter.default.post(name: .padletShowWelcome, object: nil) }
                Button("Accessibility Settings\u{2026}") { openAccessibilitySettings() }
                Divider()
                Button("Padlet on GitHub") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/\(UpdateManager.repo)")!)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")

            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .help("Quit Padlet")
        }
        .buttonStyle(.plain)
        .font(.system(size: 13))
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

extension Notification.Name {
    static let padletShowWelcome = Notification.Name("Padlet.showWelcome")
    static let padletShowSettingsWindow = Notification.Name("Padlet.showSettingsWindow")
    static let padletShowAbout = Notification.Name("Padlet.showAbout")
}

// MARK: - Main page

private struct MainPage: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var live: LiveStatus
    @ObservedObject var updates: UpdateManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if case .available(let version) = updates.state {
                UpdateBanner(version: version, updates: updates)
            }
            LevelsCard(live: live, left: prefs.edge.leftFunction, right: prefs.edge.rightFunction)
                .opacity(prefs.flags.edgeControls ? 1 : 0.5)
            EdgeControlsSection(prefs: prefs)
            Divider()
            GesturesSection(prefs: prefs)
            Divider()
            AppProfilesEntryRow(prefs: prefs) { PanelRouter.shared.go(.profiles) }
        }
        .disabled(!prefs.flags.masterEnabled)
        .opacity(prefs.flags.masterEnabled ? 1 : 0.55)
    }
}

// MARK: - Shared sections (panel + Settings window)

/// Edge functions, haptics, quick mute, media strip, sensitivity, edge width.
struct EdgeControlsSection: View {
    @ObservedObject var prefs: Preferences
    @State private var expanded: Set<String> = []

    private func isExpanded(_ key: String) -> Binding<Bool> {
        Binding(get: { expanded.contains(key) },
                set: { if $0 { expanded.insert(key) } else { expanded.remove(key) } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Edge Controls", isOn: $prefs.flags.edgeControls)
            VStack(spacing: 10) {
                edgeFunctionRow(left: true)
                edgeFunctionRow(left: false)
                HStack {
                    Spacer()
                    Button {
                        let e = prefs.edge
                        prefs.edge.leftFunction = e.rightFunction
                        prefs.edge.rightFunction = e.leftFunction
                    } label: {
                        Label("Swap Sides", systemImage: "arrow.left.arrow.right").font(.system(size: 11.5))
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.top, -6)

                SettingRow(icon: "hand.tap.fill", title: "Haptic Feedback", subtitle: "Ticks as you slide",
                           active: prefs.general.hapticStrength != .off) {
                    Picker("", selection: $prefs.general.hapticStrength) {
                        ForEach(HapticStrength.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .fixedSize()
                }
                SettingRow(icon: "square.grid.3x1.below.line.grid.1x2", title: "App Switcher",
                           subtitle: "Hold the top edge, drag to switch apps",
                           active: prefs.edge.topAppSwitcher, expanded: isExpanded("switcher")) {
                    SwitchToggle(isOn: $prefs.edge.topAppSwitcher)
                }
                if expanded.contains("switcher") {
                    SubRow(title: "Background", subtitle: switcherBackgroundNote) {
                        Picker("", selection: $prefs.edge.switcherBackground) {
                            ForEach(SwitcherBackgroundStyle.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .fixedSize()
                    }
                    .disabled(!prefs.edge.topAppSwitcher)
                }
                SettingRow(icon: "speaker.slash.fill", title: "Quick Mute",
                           subtitle: "Double-tap the top-right corner", active: prefs.edge.quickMute) {
                    SwitchToggle(isOn: $prefs.edge.quickMute)
                }
                SettingRow(icon: "forward.fill", title: "Media Strip",
                           subtitle: "Swipe the bottom edge to skip songs", active: prefs.edge.mediaStrip,
                           expanded: isExpanded("media")) {
                    SwitchToggle(isOn: $prefs.edge.mediaStrip)
                }
                if expanded.contains("media") {
                    SubRow(title: "Tap to Play or Pause", subtitle: "Double-tap the bottom edge") {
                        SwitchToggle(isOn: $prefs.edge.mediaTap)
                    }
                    SubRow(title: "Reverse Swipe", subtitle: "Swipe left for the next song") {
                        SwitchToggle(isOn: $prefs.edge.invertMediaSwipe)
                    }
                    .disabled(!prefs.edge.mediaStrip)
                }
                SliderRow(icon: "gauge.with.dots.needle.33percent", title: "Sensitivity",
                          value: $prefs.edge.sensitivity, range: 0.5...4,
                          label: String(format: "%.1f×", prefs.edge.sensitivity))
                SliderRow(icon: "arrow.left.and.right", title: "Edge Width",
                          value: $prefs.edge.edgeWidth, range: 0.03...0.15,
                          label: "\(Int((prefs.edge.edgeWidth * 100).rounded()))%")
            }
            .disabled(!prefs.flags.edgeControls)
            .opacity(prefs.flags.edgeControls ? 1 : 0.45)
        }
    }

    /// Says when Liquid Glass can't be shown and blur is used instead.
    private var switcherBackgroundNote: String? {
        guard prefs.edge.switcherBackground == .liquidGlass else { return nil }
        if #unavailable(macOS 26.0) { return "Needs macOS 26, blur is used" }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            return "Reduce Transparency is on, blur is used"
        }
        return nil
    }

    private func edgeFunctionRow(left: Bool) -> some View {
        let binding = left ? $prefs.edge.leftFunction : $prefs.edge.rightFunction
        let function = binding.wrappedValue
        return SettingRow(icon: function.symbol, title: left ? "Left Edge" : "Right Edge",
                          subtitle: prefs.edge.requireModifier ? "Slide with Fn or ⌥ held" : "Slide up or down", active: function != .off,
                          color: Theme.color(for: function)) {
            Picker("", selection: binding) {
                ForEach(EdgeFunction.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
        }
    }
}

/// The gesture families, each expandable to its slot → action pickers.
struct GesturesSection: View {
    @ObservedObject var prefs: Preferences
    var startExpanded = false
    var pickerWidth: CGFloat = 170
    @State private var expanded: Set<String> = []

    var showsHeader = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsHeader { SectionHeader("Gestures") }
            VStack(spacing: 10) {
                ForEach(GestureFamily.allCases, id: \.self) { family in
                    familyRow(family)
                }
            }
        }
        .onAppear { if startExpanded { expanded = Set(GestureFamily.allCases.map(\.rawValue)) } }
    }

    private func isExpanded(_ key: String) -> Binding<Bool> {
        Binding(get: { expanded.contains(key) },
                set: { if $0 { expanded.insert(key) } else { expanded.remove(key) } })
    }

    @ViewBuilder
    private func familyRow(_ family: GestureFamily) -> some View {
        let isOn = familyBinding(family)
        SettingRow(icon: Theme.symbol(for: family), title: Theme.title(for: family),
                   subtitle: summary(family), active: isOn.wrappedValue,
                   expanded: isExpanded(family.rawValue)) {
            SwitchToggle(isOn: isOn)
        }
        if expanded.contains(family.rawValue) {
            VStack(spacing: 4) {
                ForEach(GestureSlot.slots(in: family)) { slot in
                    ActionPickerRow(label: slot.shortTitle, action: $prefs.mapping[slot], pickerWidth: pickerWidth)
                }
            }
            .padding(.leading, 40)
            .disabled(!isOn.wrappedValue)
        }
    }

    private func familyBinding(_ family: GestureFamily) -> Binding<Bool> {
        switch family {
        case .threeFinger: return $prefs.flags.threeFinger
        case .fourFinger: return $prefs.flags.fourFinger
        case .cornerForceClick: return $prefs.flags.cornerForceClick
        case .topEdge: return $prefs.flags.topEdge
        case .twoFingerEdgeSwipe: return $prefs.flags.twoFingerEdgeSwipe
        case .threeFingerEdgeSwipe: return $prefs.flags.threeFingerEdgeSwipe
        }
    }

    private func summary(_ family: GestureFamily) -> String {
        let mapped = GestureSlot.slots(in: family)
            .map { prefs.mapping[$0] }
            .filter { $0 != .none }
        guard !mapped.isEmpty else { return Theme.subtitle(for: family) }
        return mapped.map(\.summary)
            .joined(separator: " · ")
    }
}

/// "App Profiles" switch + a chevron that opens the list.
struct AppProfilesEntryRow: View {
    @ObservedObject var prefs: Preferences
    let open: () -> Void

    var body: some View {
        SettingRow(icon: "square.stack.3d.up.fill", title: "App Profiles",
                   subtitle: profilesSubtitle, active: prefs.flags.appProfiles) {
            HStack(spacing: 8) {
                SwitchToggle(isOn: $prefs.flags.appProfiles)
                Button(action: open) {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Edit app profiles")
            }
        }
    }

    private var profilesSubtitle: String {
        let n = prefs.profiles.count
        return n == 0 ? "Different gestures in specific apps" : "\(n) app\(n == 1 ? "" : "s") customized"
    }
}

// MARK: - Settings page

private struct SettingsPage: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var live: LiveStatus
    @ObservedObject var updates: UpdateManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EdgeBehaviorSection(prefs: prefs)
            Divider()
            GeneralSection(prefs: prefs, live: live)
            Divider()
            UpdatesSection(prefs: prefs, updates: updates)
            Button {
                NotificationCenter.default.post(name: .padletShowSettingsWindow, object: nil)
            } label: {
                Label("Open Settings Window", systemImage: "macwindow")
            }
            .buttonStyle(.link)
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 2)
        }
    }
}

/// Where edges respond and how sliding behaves.
struct EdgeBehaviorSection: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Edge Gestures")
            VStack(spacing: 10) {
                SettingRow(icon: "rectangle.bottomthird.inset.filled", title: "Bottom Quarter Only",
                           subtitle: "Ignore touches above the lower 25%",
                           active: prefs.edge.bottomQuarterOnly, tinted: false) {
                    SwitchToggle(isOn: $prefs.edge.bottomQuarterOnly)
                }
                SettingRow(icon: "option", title: "Require Fn or ⌥",
                           subtitle: "Only slide while holding a modifier",
                           active: prefs.edge.requireModifier, tinted: false) {
                    SwitchToggle(isOn: $prefs.edge.requireModifier)
                }
            }

            Divider()
            SectionHeader("While Sliding")
            VStack(spacing: 10) {
                SettingRow(icon: "cursorarrow", title: "Freeze Cursor",
                           subtitle: "Pointer stays put while sliding", active: prefs.edge.freezeCursor) {
                    SwitchToggle(isOn: $prefs.edge.freezeCursor)
                }
                SettingRow(icon: "dial.low.fill", title: "Always Fine Control",
                           subtitle: "Quarter steps without holding ⇧⌥", active: prefs.edge.fineControlAlways) {
                    SwitchToggle(isOn: $prefs.edge.fineControlAlways)
                }
                SliderRow(icon: "keyboard", title: "Typing Guard",
                          value: $prefs.edge.typingGuardMs, range: 0...1000,
                          label: "\(Int(prefs.edge.typingGuardMs / 10) * 10) ms")
            }
        }
    }
}

/// Appearance, login item, welcome guide.
struct GeneralSection: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var live: LiveStatus
    @State private var loginError: String?

    var showsHeader = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsHeader { SectionHeader("General") }
            VStack(spacing: 10) {
                SettingRow(icon: "circle.lefthalf.filled", title: "Appearance", subtitle: nil,
                           active: false, tinted: false) {
                    Picker("", selection: $prefs.general.appearance) {
                        ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .fixedSize()
                }
                SettingRow(icon: "power", title: "Open at Login",
                           subtitle: loginError ?? "Start Padlet when you log in",
                           active: live.launchAtLogin) {
                    SwitchToggle(isOn: Binding(
                        get: { live.launchAtLogin },
                        set: { newValue in
                            loginError = LaunchAtLogin.set(newValue)
                            live.refresh()
                        }))
                }
                SettingRow(icon: "command", title: "Turn On / Off Shortcut",
                           subtitle: "Works from any app", active: prefs.general.toggleHotKey != nil,
                           tinted: false) {
                    KeyComboRecorder(combo: $prefs.general.toggleHotKey, placeholder: "Record",
                                     requiresModifier: true)
                }
                SettingRow(icon: "sparkles", title: "Welcome Guide",
                           subtitle: "Replay the introduction", active: false, tinted: false) {
                    Button("Show") { NotificationCenter.default.post(name: .padletShowWelcome, object: nil) }
                        .controlSize(.small)
                }
            }
        }
    }
}

/// Automatic update switches and the current status.
struct UpdatesSection: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var updates: UpdateManager

    var showsHeader = true
    /// The About pane shows the status itself, so it hides this row.
    var showsStatus = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsHeader { SectionHeader("Updates") }
            VStack(spacing: 10) {
                SettingRow(icon: "arrow.triangle.2.circlepath", title: "Check Automatically",
                           subtitle: "Looks for a new release every 6 hours",
                           active: prefs.general.autoCheckUpdates) {
                    SwitchToggle(isOn: $prefs.general.autoCheckUpdates)
                }
                SettingRow(icon: "square.and.arrow.down.fill", title: "Install Automatically",
                           subtitle: "Update and relaunch without asking",
                           active: prefs.general.autoInstallUpdates) {
                    SwitchToggle(isOn: $prefs.general.autoInstallUpdates)
                }
                .disabled(!prefs.general.autoCheckUpdates)
                if showsStatus { UpdateStatusRow(updates: updates) }
            }
        }
    }
}

// MARK: - Profiles

struct ProfilesPage: View {
    @ObservedObject var prefs: Preferences
    var open: (UUID) -> Void = { PanelRouter.shared.go(.profile($0)) }
    @ObservedObject private var tracker = FrontmostAppTracker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Give gestures a different action while a specific app is in front. Anything you leave on Default uses your main settings.")
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !prefs.flags.appProfiles {
                Label("App profiles are turned off", systemImage: "exclamationmark.circle")
                    .font(.system(size: 11.5))
                    .foregroundColor(.orange)
            }

            if prefs.profiles.isEmpty {
                Card {
                    VStack(spacing: 6) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 26))
                            .foregroundColor(.secondary)
                        Text("No app profiles yet").font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach($prefs.profiles) { $profile in
                        ProfileRow(profile: $profile, open: open)
                    }
                }
            }

            HStack {
                if let app = tracker.lastExternalApp, !prefs.profiles.contains(where: { $0.bundleID == app.bundleID }) {
                    Button { add(app) } label: {
                        Label("Add \(app.name)", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button { chooseApp(add) } label: { Label("Choose App\u{2026}", systemImage: "folder") }
                Spacer()
            }
            .controlSize(.small)
        }
    }

    private func add(_ app: AppInfo) {
        if let existing = prefs.profiles.first(where: { $0.bundleID == app.bundleID }) {
            open(existing.id)
            return
        }
        let profile = AppProfile(bundleID: app.bundleID, name: app.name)
        prefs.profiles.append(profile)
        open(profile.id)
    }
}

private struct ProfileRow: View {
    @Binding var profile: AppProfile
    let open: (UUID) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppInfo(bundleID: profile.bundleID).icon)
                .resizable()
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name).font(.system(size: 13, weight: .medium))
                Text(profile.overrides.isEmpty ? "No changes yet" :
                        "\(profile.overrides.count) gesture\(profile.overrides.count == 1 ? "" : "s") changed")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            SwitchToggle(isOn: $profile.enabled)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
        .contentShape(Rectangle())
        .onTapGesture { open(profile.id) }
    }
}

struct ProfileDetailPage: View {
    @ObservedObject var prefs: Preferences
    let profileID: UUID
    var pickerWidth: CGFloat = 170
    var close: () -> Void = { PanelRouter.shared.go(.profiles) }

    var body: some View {
        if let index = prefs.profiles.firstIndex(where: { $0.id == profileID }) {
            let profile = prefs.profiles[index]
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(nsImage: AppInfo(bundleID: profile.bundleID).icon)
                        .resizable()
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(profile.name).font(.system(size: 14, weight: .semibold))
                        Text(profile.bundleID).font(.system(size: 10.5)).foregroundColor(.secondary)
                    }
                    Spacer()
                    SwitchToggle(isOn: $prefs.profiles[index].enabled)
                }

                ForEach(GestureFamily.allCases, id: \.self) { family in
                    SectionHeader(Theme.title(for: family))
                    VStack(spacing: 4) {
                        ForEach(GestureSlot.slots(in: family)) { slot in
                            OverridePickerRow(label: slot.shortTitle,
                                              defaultAction: prefs.mapping[slot],
                                              override: $prefs.profiles[index][slot],
                                              pickerWidth: pickerWidth)
                        }
                    }
                    .opacity(prefs.flags.isEnabled(family) ? 1 : 0.5)
                }

                HStack {
                    Button("Reset All") { prefs.profiles[index].overrides = [:] }
                        .disabled(profile.overrides.isEmpty)
                    Spacer()
                    Button(role: .destructive) {
                        prefs.profiles.remove(at: index)
                        close()
                    } label: {
                        Label("Remove Profile", systemImage: "trash")
                    }
                }
                .controlSize(.small)
                .padding(.top, 4)
            }
        } else {
            Text("This profile no longer exists.")
                .foregroundColor(.secondary)
                .onAppear(perform: close)
        }
    }
}

// MARK: - Pieces

struct StatusPill: View {
    let enabled: Bool
    let granted: Bool

    var body: some View {
        let (color, text): (Color, String) =
            !granted ? (.orange, "Needs Access") :
            enabled ? (.green, "Ready") : (.secondary, "Off")
        Button {
            if !granted { openAccessibilitySettings() }
        } label: {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(text).font(.system(size: 12)).foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help(granted ? "" : "Grant Accessibility access in System Settings")
    }
}

/// The two side edges, each next to its function and live level.
struct LevelsCard: View {
    @ObservedObject var live: LiveStatus
    let left: EdgeFunction
    let right: EdgeFunction

    var body: some View {
        Card {
            HStack(spacing: 0) {
                EdgeMeter(value: value(left), color: Theme.color(for: left))
                readout(left, alignment: .leading).padding(.leading, 12)
                Spacer()
                readout(right, alignment: .trailing).padding(.trailing, 12)
                EdgeMeter(value: value(right), color: Theme.color(for: right))
            }
            .frame(height: 76)
        }
    }

    private func value(_ f: EdgeFunction) -> Float? {
        if f == .volume && live.muted { return 0 }
        return live.levels[f]
    }

    private func readout(_ f: EdgeFunction, alignment: HorizontalAlignment) -> some View {
        let symbol = (f == .volume && live.muted) ? "speaker.slash.fill" : f.symbol
        let v = value(f)
        return VStack(alignment: alignment, spacing: 4) {
            HStack(spacing: 5) {
                if alignment == .leading { Image(systemName: symbol).foregroundColor(Theme.color(for: f)) }
                Text(f.title.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .kerning(0.8)
                    .foregroundColor(.secondary)
                if alignment == .trailing { Image(systemName: symbol).foregroundColor(Theme.color(for: f)) }
            }
            .font(.system(size: 11))
            if f.kind == .level {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(v.map { "\(Int(($0 * 100).rounded()))" } ?? "—")
                        .font(.system(size: 32, weight: .regular, design: .rounded))
                        .monospacedDigit()
                    if v != nil {
                        Text("%")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                if v == nil {
                    Text("Not available here").font(.system(size: 10)).foregroundColor(.secondary)
                }
            } else {
                Image(systemName: f.symbol)
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(f == .off ? .secondary : .primary)
                    .frame(height: 38)
            }
        }
    }

    private struct EdgeMeter: View {
        let value: Float?
        let color: Color

        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .bottom, endPoint: .top))
                        .frame(height: geo.size.height * CGFloat(value ?? 0))
                        .animation(.easeOut(duration: 0.2), value: value)
                }
            }
            .frame(width: 5)
        }
    }
}

struct UpdateBanner: View {
    let version: String
    @ObservedObject var updates: UpdateManager

    var body: some View {
        HStack(spacing: 10) {
            IconBadge(symbol: "arrow.down.circle.fill", active: true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Padlet \(version) is available").font(.system(size: 13, weight: .medium))
                Text("You have \(updates.currentVersion)").font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            Button("Update") { updates.install() }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent.opacity(0.12)))
    }
}

struct UpdateStatusRow: View {
    @ObservedObject var updates: UpdateManager

    var body: some View {
        HStack {
            Text(statusText)
                .font(.system(size: 11))
                .foregroundColor(isError ? .orange : .secondary)
                .lineLimit(2)
            Spacer()
            switch updates.state {
            case .available:
                Button("Install") { updates.install() }.buttonStyle(.borderedProminent)
            case .checking, .downloading, .installing:
                ProgressView().controlSize(.small)
            default:
                Button("Check Now") { updates.check(userInitiated: true) }
            }
        }
        .controlSize(.small)
        .padding(.leading, 40)
    }

    private var isError: Bool {
        if case .failed = updates.state { return true }
        return false
    }

    private var statusText: String {
        switch updates.state {
        case .idle: return "Version \(updates.currentVersion)"
        case .checking: return "Checking for updates\u{2026}"
        case .upToDate: return "You're up to date (\(updates.currentVersion))"
        case .available(let v): return "Version \(v) is available"
        case .downloading: return "Downloading update\u{2026}"
        case .installing: return "Installing — Padlet will relaunch"
        case .failed(let message): return "Update failed: \(message)"
        }
    }
}
