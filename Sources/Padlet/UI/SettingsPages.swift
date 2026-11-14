// UI/SettingsPages.swift
// The Settings window's own pages, as stock grouped forms (hub rules design.md + app-shell.md: native
// controls, nothing restyled). They edit the same Preferences fields as the menu bar panel's card
// sections in PanelView.swift, which keep their own look.

import AppKit
import AppShellCore
import SettingsKit
import SwiftUI

// MARK: - General

struct GeneralSettingsPage: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var live: LiveStatus

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $prefs.flags.masterEnabled) {
                    Text("Padlet")
                    Text(prefs.flags.masterEnabled ? "Gestures and edge controls are on" : "Everything is off")
                }
                if !live.accessibilityGranted {
                    LabeledContent {
                        Button("Open Settings") { openAccessibilitySettings() }
                    } label: {
                        Label("Accessibility access needed", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Padlet can't see the trackpad until you allow it")
                    }
                    LabeledContent("Already allowed but still asked?") {
                        Button("Reset and ask again") { PermissionsManager().resetAndRequest() }
                    }
                }
            }
            Section {
                Picker("Appearance", selection: $prefs.general.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                LaunchAtLoginRow(appName: "Padlet")
                LabeledContent {
                    KeyComboRecorder(combo: $prefs.general.toggleHotKey, placeholder: "Record", requiresModifier: true)
                } label: {
                    Text("Turn on or off shortcut")
                    Text("Works from any app")
                }
                LabeledContent("Welcome guide") {
                    Button("Show") { NotificationCenter.default.post(name: .padletShowWelcome, object: nil) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Edge controls

struct EdgeSettingsPage: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var live: LiveStatus

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $prefs.flags.edgeControls) {
                    Text("Edge controls")
                    Text(prefs.edge.requireModifier ? "Slide along a side edge with Fn or ⌥ held"
                                                    : "Slide up or down along a side edge")
                }
            }
            Group {
                Section("Side edges") {
                    edgePicker("Left edge", $prefs.edge.leftFunction)
                    edgePicker("Right edge", $prefs.edge.rightFunction)
                    LabeledContent("") {
                        Button {
                            let e = prefs.edge
                            prefs.edge.leftFunction = e.rightFunction
                            prefs.edge.rightFunction = e.leftFunction
                        } label: {
                            Label("Swap sides", systemImage: "arrow.left.arrow.right")
                        }
                    }
                    Picker("Haptic feedback", selection: $prefs.general.hapticStrength) {
                        ForEach(HapticStrength.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section {
                    Toggle(isOn: $prefs.edge.topAppSwitcher) {
                        Text("App switcher")
                        Text("Hold the top edge, drag to switch apps")
                    }
                    Picker("Switcher background", selection: $prefs.edge.switcherBackground) {
                        ForEach(SwitcherBackgroundStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .disabled(!prefs.edge.topAppSwitcher)
                } header: {
                    Text("Top edge")
                } footer: {
                    if let note = switcherBackgroundNote { Text(note).frame(maxWidth: .infinity, alignment: .leading) }
                }
                Section("Corners and bottom edge") {
                    Toggle(isOn: $prefs.edge.quickMute) {
                        Text("Quick mute")
                        Text("Double-tap the top-right corner")
                    }
                    Toggle(isOn: $prefs.edge.mediaStrip) {
                        Text("Media strip")
                        Text("Swipe the bottom edge to skip songs")
                    }
                    Toggle(isOn: $prefs.edge.mediaTap) {
                        Text("Tap to play or pause")
                        Text("Double-tap the bottom edge")
                    }
                    .disabled(!prefs.edge.mediaStrip)
                    Toggle(isOn: $prefs.edge.invertMediaSwipe) {
                        Text("Reverse swipe")
                        Text("Swipe left for the next song")
                    }
                    .disabled(!prefs.edge.mediaStrip)
                }
                Section("Feel") {
                    sliderRow("Sensitivity", $prefs.edge.sensitivity, 0.5...4,
                              String(format: "%.1f×", prefs.edge.sensitivity))
                    sliderRow("Edge width", $prefs.edge.edgeWidth, 0.03...0.15,
                              "\(Int((prefs.edge.edgeWidth * 100).rounded()))%")
                }
            }
            .disabled(!prefs.flags.edgeControls)
            Section("Where edges respond") {
                Toggle(isOn: $prefs.edge.bottomQuarterOnly) {
                    Text("Bottom quarter only")
                    Text("Ignore touches above the lower 25%")
                }
                Toggle(isOn: $prefs.edge.requireModifier) {
                    Text("Require Fn or ⌥")
                    Text("Only slide while holding a modifier")
                }
            }
            Section("While sliding") {
                Toggle(isOn: $prefs.edge.freezeCursor) {
                    Text("Freeze cursor")
                    Text("The pointer stays put while sliding")
                }
                Toggle(isOn: $prefs.edge.fineControlAlways) {
                    Text("Always fine control")
                    Text("Quarter steps without holding ⇧⌥")
                }
                sliderRow("Typing guard", $prefs.edge.typingGuardMs, 0...1000,
                          "\(Int(prefs.edge.typingGuardMs / 10) * 10) ms")
            }
        }
        .formStyle(.grouped)
        .disabled(!prefs.flags.masterEnabled)
    }

    private func edgePicker(_ title: String, _ binding: Binding<EdgeFunction>) -> some View {
        Picker(title, selection: binding) {
            ForEach(EdgeFunction.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
        }
    }

    private func sliderRow<V: BinaryFloatingPoint>(_ title: String, _ value: Binding<V>,
                                                     _ range: ClosedRange<V>, _ label: String) -> some View
        where V.Stride: BinaryFloatingPoint {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range)
                Text(label)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 52, alignment: .trailing)
            }
        }
    }

    /// Says when Liquid Glass can't be shown and blur is used instead.
    private var switcherBackgroundNote: String? {
        guard prefs.edge.switcherBackground == .liquidGlass else { return nil }
        if #unavailable(macOS 26.0) { return "Liquid Glass needs macOS 26, so blur is used" }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            return "Reduce Transparency is on, so blur is used"
        }
        return nil
    }
}

// MARK: - Gestures

struct GestureSettingsPage: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            ForEach(GestureFamily.allCases, id: \.self) { family in
                Section {
                    Toggle(isOn: familyBinding(family)) {
                        Text(Theme.title(for: family))
                        Text(Theme.subtitle(for: family))
                    }
                    ForEach(GestureSlot.slots(in: family)) { slot in
                        ActionFormRow(title: slot.shortTitle, action: $prefs.mapping[slot])
                    }
                    .disabled(!familyBinding(family).wrappedValue)
                } footer: {
                    if family == GestureFamily.allCases.last {
                        Text("Window actions work on the front window of the app you're using.")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .disabled(!prefs.flags.masterEnabled)
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
}

/// One gesture slot in a form: a native menu picker, with the extra input (keys, app, text…) under it.
struct ActionFormRow: View {
    let title: String
    @Binding var action: GestureAction

    var body: some View {
        Picker(title, selection: Binding(
            get: { action.pickerValue },
            set: { action = action.replacing(withPicked: $0) })) {
            ActionMenuItems()
        }
        if action.hasDetailField {
            LabeledContent("") { ActionDetailField(action: $action).labelsHidden() }
        }
    }
}

/// Like ActionFormRow, but "Default (…)" means the profile uses the main setting.
struct OverrideFormRow: View {
    let title: String
    let defaultAction: GestureAction
    @Binding var override: GestureAction?

    var body: some View {
        Picker(selection: Binding<GestureAction>(
            get: { override?.pickerValue ?? Self.useDefault },
            set: { picked in
                guard picked != Self.useDefault else { override = nil; return }
                override = (override ?? picked).replacing(withPicked: picked)
            })) {
            Text("Default (\(defaultAction.summary))").tag(Self.useDefault)
            Divider()
            ActionMenuItems()
        } label: {
            Text(title).foregroundStyle(override == nil ? .secondary : .primary)
        }
        if let current = override, current.hasDetailField {
            LabeledContent("") {
                ActionDetailField(action: Binding(get: { override ?? .none }, set: { override = $0 }))
                    .labelsHidden()
            }
        }
    }

    /// Sentinel tag for "use the default" (an empty shortcut name never reaches storage).
    private static let useDefault = GestureAction.runShortcut(name: "\u{0}default")
}

extension GestureAction {
    /// Whether ActionDetailField shows anything for this action.
    var hasDetailField: Bool {
        switch self {
        case .keystroke, .openApp, .runShortcut, .openURL, .pasteText, .runCommand, .builtin(.toggleDoNotDisturb):
            return true
        default:
            return false
        }
    }
}

// MARK: - App profiles

struct ProfilesSettingsPage: View {
    @ObservedObject var prefs: Preferences
    let open: (UUID) -> Void
    @ObservedObject private var tracker = FrontmostAppTracker.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $prefs.flags.appProfiles) {
                    Text("App profiles")
                    Text("Give gestures a different action while a specific app is in front. Anything left on Default uses your main settings.")
                }
            }
            Section("Apps") {
                if prefs.profiles.isEmpty {
                    Text("No app profiles yet").foregroundStyle(.secondary)
                } else {
                    ForEach($prefs.profiles) { $profile in
                        LabeledContent {
                            HStack {
                                Toggle("", isOn: $profile.enabled).labelsHidden().toggleStyle(.switch)
                                Button("Edit") { open(profile.id) }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(nsImage: AppInfo(bundleID: profile.bundleID).icon)
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                VStack(alignment: .leading) {
                                    Text(profile.name)
                                    Text(profile.overrides.isEmpty ? "No changes yet" :
                                            "\(profile.overrides.count) gesture\(profile.overrides.count == 1 ? "" : "s") changed")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                HStack {
                    if let app = tracker.lastExternalApp, !prefs.profiles.contains(where: { $0.bundleID == app.bundleID }) {
                        Button { add(app) } label: { Label("Add \(app.name)", systemImage: "plus") }
                    }
                    Button { chooseApp(add) } label: { Label("Choose app\u{2026}", systemImage: "folder") }
                }
            }
        }
        .formStyle(.grouped)
        .disabled(!prefs.flags.masterEnabled)
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

struct ProfileDetailSettingsPage: View {
    @ObservedObject var prefs: Preferences
    let profileID: UUID
    let close: () -> Void
    @State private var confirmRemove = false

    var body: some View {
        if let index = prefs.profiles.firstIndex(where: { $0.id == profileID }) {
            let profile = prefs.profiles[index]
            Form {
                Section {
                    Button { close() } label: { Label("All profiles", systemImage: "chevron.left") }
                        .buttonStyle(.link)
                    Toggle(isOn: $prefs.profiles[index].enabled) {
                        HStack(spacing: 8) {
                            Image(nsImage: AppInfo(bundleID: profile.bundleID).icon)
                                .resizable()
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading) {
                                Text(profile.name).font(.headline)
                                Text(profile.bundleID).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                ForEach(GestureFamily.allCases, id: \.self) { family in
                    Section {
                        ForEach(GestureSlot.slots(in: family)) { slot in
                            OverrideFormRow(title: slot.shortTitle, defaultAction: prefs.mapping[slot],
                                            override: $prefs.profiles[index][slot])
                        }
                    } header: {
                        Text(Theme.title(for: family))
                    } footer: {
                        if !prefs.flags.isEnabled(family) {
                            Text("\(Theme.title(for: family)) is turned off in Gestures")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                Section {
                    HStack {
                        Button("Reset all") { prefs.profiles[index].overrides = [:] }
                            .disabled(profile.overrides.isEmpty)
                        Spacer()
                        Button("Remove profile\u{2026}", role: .destructive) { confirmRemove = true }
                    }
                }
            }
            .formStyle(.grouped)
            .confirmationDialog("Remove the \(profile.name) profile?", isPresented: $confirmRemove) {
                Button("Remove", role: .destructive) {
                    prefs.profiles.remove(at: index)
                    close()
                }
            } message: {
                Text("Its \(profile.overrides.count) gesture change\(profile.overrides.count == 1 ? "" : "s") will be lost.")
            }
        } else {
            Text("This profile no longer exists.")
                .foregroundStyle(.secondary)
                .onAppear(perform: close)
        }
    }
}
