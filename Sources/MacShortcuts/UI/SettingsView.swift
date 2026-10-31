// UI/SettingsView.swift
// The menu bar panel (shown in a popover when you click the menu bar icon).
//
//   Main page      — status + master switch, live brightness/volume, edge controls,
//                    gesture families and their action mappings.
//   Settings page  — set-once options: edge behaviour, while-sliding options,
//                    appearance, open at login, updates.
//
// Every control writes straight to Preferences.shared, which persists it and pushes it
// to GestureCoordinator — there is no Save button.

import SwiftUI
import AppKit

// MARK: - Theme

enum Theme {
    static let accent = Color(red: 0.36, green: 0.35, blue: 0.94)
    static let warm = Color(red: 1.0, green: 0.62, blue: 0.04)
    static let cool = Color(red: 0.19, green: 0.65, blue: 1.0)
    static let panelWidth: CGFloat = 340
}

// MARK: - Live levels (polled while the panel is open)

final class LiveStatus: ObservableObject {
    @Published var brightness: Float?
    @Published var volume: Float?
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
        brightness = BrightnessControl.get()
        volume = VolumeControl.get()
        muted = VolumeControl.isMuted() ?? false
        accessibilityGranted = PermissionsManager.isAccessibilityGranted()
        launchAtLogin = LaunchAtLogin.isEnabled
    }
}

// MARK: - Root

struct SettingsView: View {

    enum Page { case main, settings }

    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var updates = UpdateManager.shared
    @StateObject private var live = LiveStatus()
    @State private var page: Page

    init(page: Page = .main) {
        _page = State(initialValue: page)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case .main: MainPage(prefs: prefs, live: live, updates: updates)
                case .settings: SettingsPage(prefs: prefs, live: live, updates: updates)
                }
            }
            .transition(.opacity)

            Divider().padding(.horizontal, 14)
            footer
        }
        .frame(width: Theme.panelWidth)
        .tint(Theme.accent)
        .onAppear { live.start() }
        .onDisappear { live.stop() }
        .onReceive(NotificationCenter.default.publisher(for: .showSettingsPage)) { _ in
            page = .settings
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if page == .main {
                Button { withAnimation(.easeInOut(duration: 0.15)) { page = .settings } } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            } else {
                Button { withAnimation(.easeInOut(duration: 0.15)) { page = .main } } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                Text("Version \(updates.currentVersion)")
                    .foregroundColor(.secondary)
            }
            Spacer()
            Menu {
                Button("Check for Updates…") { updates.check(userInitiated: true) }
                Button("Accessibility Settings…") { openAccessibilitySettings() }
                Button("Release Notes on GitHub") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/\(UpdateManager.repo)/releases")!)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")

            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .help("Quit Mac Shortcuts")
        }
        .buttonStyle(.plain)
        .font(.system(size: 13))
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

extension Notification.Name {
    static let showSettingsPage = Notification.Name("MacShortcuts.showSettingsPage")
}

func openAccessibilitySettings() {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
}

// MARK: - Main page

private struct MainPage: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var live: LiveStatus
    @ObservedObject var updates: UpdateManager
    @State private var mediaExpanded = false
    @State private var threeFingerExpanded = false
    @State private var cornersExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if case .available(let version) = updates.state { UpdateBanner(version: version, updates: updates) }
            LevelsCard(live: live, swapSides: prefs.edge.swapSides)
                .opacity(prefs.flags.masterEnabled && prefs.flags.edgeControls ? 1 : 0.5)

            Group {
                SectionHeader("Edge Controls", isOn: $prefs.flags.edgeControls)
                VStack(spacing: 10) {
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
                    SettingRow(icon: "speaker.slash.fill", title: "Quick Mute",
                               subtitle: "Double-tap the top-right corner", active: prefs.edge.quickMute) {
                        SwitchToggle(isOn: $prefs.edge.quickMute)
                    }
                    SettingRow(icon: "forward.fill", title: "Media Strip",
                               subtitle: "Swipe the bottom edge to skip songs", active: prefs.edge.mediaStrip,
                               expanded: $mediaExpanded) {
                        SwitchToggle(isOn: $prefs.edge.mediaStrip)
                    }
                    if mediaExpanded {
                        SubRow(title: "Tap to Play or Pause", subtitle: "Double-tap the bottom edge") {
                            SwitchToggle(isOn: $prefs.edge.mediaTap)
                        }
                        SubRow(title: "Reverse Swipe", subtitle: "Swipe left for the next song") {
                            SwitchToggle(isOn: $prefs.edge.invertMediaSwipe)
                        }
                        .disabled(!prefs.edge.mediaStrip)
                    }

                    Divider()

                    SliderRow(icon: "gauge.with.dots.needle.33percent", title: "Sensitivity",
                              value: $prefs.edge.sensitivity, range: 0.5...4, step: 0.25,
                              label: String(format: "%.2g×", prefs.edge.sensitivity))
                    SliderRow(icon: "arrow.left.and.right", title: "Edge Width",
                              value: $prefs.edge.edgeWidth, range: 0.03...0.15, step: 0.01,
                              label: "\(Int((prefs.edge.edgeWidth * 100).rounded()))%")
                }
                .disabled(!prefs.flags.edgeControls)
                .opacity(prefs.flags.edgeControls ? 1 : 0.45)
            }

            Divider()

            VStack(spacing: 10) {
                SettingRow(icon: "hand.raised.fingers.spread.fill", title: "Three-Finger Tap / Click",
                           subtitle: summary(prefs.mapping.threeFingerTap, prefs.mapping.threeFingerClick),
                           active: prefs.flags.threeFinger, expanded: $threeFingerExpanded) {
                    SwitchToggle(isOn: $prefs.flags.threeFinger)
                }
                if threeFingerExpanded {
                    VStack(spacing: 4) {
                        GestureSlotRow(label: "Tap", action: $prefs.mapping.threeFingerTap)
                        GestureSlotRow(label: "Click (hold)", action: $prefs.mapping.threeFingerClick)
                    }
                    .padding(.leading, 40)
                    .disabled(!prefs.flags.threeFinger)
                }
                SettingRow(icon: "square.dashed.inset.filled", title: "Corner Force Click",
                           subtitle: "Press hard in a trackpad corner",
                           active: prefs.flags.cornerForceClick, expanded: $cornersExpanded) {
                    SwitchToggle(isOn: $prefs.flags.cornerForceClick)
                }
                if cornersExpanded {
                    VStack(spacing: 4) {
                        GestureSlotRow(label: "Top Left", action: $prefs.mapping.cornerTopLeft)
                        GestureSlotRow(label: "Top Right", action: $prefs.mapping.cornerTopRight)
                        GestureSlotRow(label: "Bottom Left", action: $prefs.mapping.cornerBottomLeft)
                        GestureSlotRow(label: "Bottom Right", action: $prefs.mapping.cornerBottomRight)
                    }
                    .padding(.leading, 40)
                    .disabled(!prefs.flags.cornerForceClick)
                }
            }
        }
        .disabled(!prefs.flags.masterEnabled)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .overlay(alignment: .top) { headerOverlay }   // header stays enabled when master is off
    }

    // The header lives in an overlay so the master switch is never disabled.
    private var header: some View {
        Color.clear.frame(height: 30)
    }

    private var headerOverlay: some View {
        HStack(spacing: 9) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 24, height: 24)
            Text("Mac Shortcuts")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            StatusPill(enabled: prefs.flags.masterEnabled, granted: live.accessibilityGranted)
            SwitchToggle(isOn: $prefs.flags.masterEnabled)
                .help("Turn every gesture on or off")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private func summary(_ tap: GestureAction, _ click: GestureAction) -> String {
        "Tap: \(tap.displayName.replacingOccurrences(of: "…", with: "")) · Click: \(click.displayName.replacingOccurrences(of: "…", with: ""))"
    }
}

// MARK: - Settings page

private struct SettingsPage: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var live: LiveStatus
    @ObservedObject var updates: UpdateManager
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 24, height: 24)
                Text("Settings")
                    .font(.system(size: 15, weight: .semibold))
            }

            SectionHeader("Edge Gestures")
            VStack(spacing: 10) {
                SettingRow(icon: "arrow.left.arrow.right", title: "Swap Sides",
                           subtitle: prefs.edge.swapSides ? "Left: Volume · Right: Brightness"
                                                          : "Left: Brightness · Right: Volume",
                           active: prefs.edge.swapSides, tinted: false) {
                    SwitchToggle(isOn: $prefs.edge.swapSides)
                }
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
                          value: $prefs.edge.typingGuardMs, range: 0...1000, step: 50,
                          label: "\(Int(prefs.edge.typingGuardMs)) ms")
            }

            Divider()
            SectionHeader("General")
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
                SettingRow(icon: "power", title: "Open at Login", subtitle: loginError,
                           active: live.launchAtLogin) {
                    SwitchToggle(isOn: Binding(
                        get: { live.launchAtLogin },
                        set: { newValue in
                            loginError = LaunchAtLogin.set(newValue)
                            live.refresh()
                        }))
                }
            }

            Divider()
            SectionHeader("Updates")
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
                UpdateStatusRow(updates: updates)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
}

// MARK: - Components

private struct StatusPill: View {
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

/// Brightness and volume, each next to the edge that controls it.
private struct LevelsCard: View {
    @ObservedObject var live: LiveStatus
    let swapSides: Bool

    var body: some View {
        let brightness = Level(title: "BRIGHTNESS", icon: "sun.max.fill", value: live.brightness, color: Theme.warm)
        let volume = Level(title: "VOLUME", icon: live.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                           value: live.muted ? 0 : live.volume, color: Theme.cool)
        let (left, right) = swapSides ? (volume, brightness) : (brightness, volume)

        HStack(spacing: 0) {
            EdgeBar(value: left.value, color: left.color)
            levelText(left, alignment: .leading).padding(.leading, 12)
            Spacer()
            levelText(right, alignment: .trailing).padding(.trailing, 12)
            EdgeBar(value: right.value, color: right.color)
        }
        .padding(10)
        .frame(height: 96)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07))
        )
    }

    private struct Level {
        let title: String
        let icon: String
        let value: Float?
        let color: Color
    }

    private func levelText(_ level: Level, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            HStack(spacing: 5) {
                if alignment == .leading { Image(systemName: level.icon).foregroundColor(level.color) }
                Text(level.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .kerning(0.8)
                    .foregroundColor(.secondary)
                if alignment == .trailing { Image(systemName: level.icon).foregroundColor(level.color) }
            }
            .font(.system(size: 11))
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(level.value.map { "\(Int(($0 * 100).rounded()))" } ?? "—")
                    .font(.system(size: 34, weight: .regular, design: .rounded))
                    .monospacedDigit()
                Text("%")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .opacity(level.value == nil ? 0 : 1)
            }
            if level.value == nil {
                Text("Not available here")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    private struct EdgeBar: View {
        let value: Float?
        let color: Color

        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .bottom, endPoint: .top))
                        .frame(height: geo.size.height * CGFloat(value ?? 0))
                        .animation(.easeOut(duration: 0.2), value: value)
                }
            }
            .frame(width: 5)
        }
    }
}

private struct UpdateBanner: View {
    let version: String
    @ObservedObject var updates: UpdateManager

    var body: some View {
        HStack(spacing: 10) {
            IconBadge(symbol: "arrow.down.circle.fill", active: true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Version \(version) is available").font(.system(size: 13, weight: .medium))
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

private struct UpdateStatusRow: View {
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
        case .checking: return "Checking for updates…"
        case .upToDate: return "You're up to date (\(updates.currentVersion))"
        case .available(let v): return "Version \(v) is available"
        case .downloading: return "Downloading update…"
        case .installing: return "Installing — Mac Shortcuts will relaunch"
        case .failed(let message): return "Update failed: \(message)"
        }
    }
}

private struct SectionHeader: View {
    let title: String
    var isOn: Binding<Bool>?

    init(_ title: String, isOn: Binding<Bool>? = nil) {
        self.title = title
        self.isOn = isOn
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            Spacer()
            if let isOn = isOn { SwitchToggle(isOn: isOn) }
        }
    }
}

private struct IconBadge: View {
    let symbol: String
    let active: Bool
    var tinted: Bool = true

    var body: some View {
        let filled = active && tinted
        ZStack {
            Circle().fill(filled ? Theme.accent : Color.primary.opacity(0.09))
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(filled ? .white : .primary.opacity(0.75))
        }
        .frame(width: 28, height: 28)
        .animation(.easeOut(duration: 0.15), value: filled)
    }
}

private struct SettingRow<Trailing: View>: View {
    let icon: String
    let title: String
    let subtitle: String?
    let active: Bool
    var tinted: Bool = true
    var expanded: Binding<Bool>? = nil
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: icon, active: active, tinted: tinted)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    if let expanded = expanded {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { expanded.wrappedValue.toggle() }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                                .rotationEffect(.degrees(expanded.wrappedValue ? 180 : 0))
                                .padding(3)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let subtitle = subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

private struct SubRow<Trailing: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5))
                if let subtitle = subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            Spacer()
            trailing()
        }
        .padding(.leading, 40)
    }
}

private struct SliderRow: View {
    let icon: String
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                IconBadge(symbol: icon, active: false, tinted: false)
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            Slider(value: $value, in: range)
                .controlSize(.small)
                .padding(.leading, 40)
        }
    }
}

private struct SwitchToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
    }
}

// MARK: - GestureSlotRow

/// A gesture name with a compact action picker; extra input (key / app) appears below.
private struct GestureSlotRow: View {

    let label: String
    @Binding var action: GestureAction

    // Normalizes the action so the Picker always highlights the correct row.
    // openApp("com.foo") → openApp(""); keystroke("x", []) → keystroke("", []).
    // On set, an existing associated value is kept when re-selecting the same category.
    private var normalizedActionBinding: Binding<GestureAction> {
        Binding(
            get: {
                switch action {
                case .openApp:   return .openApp(bundleID: "")
                case .keystroke: return .keystroke(key: "", modifiers: [])
                default:         return action
                }
            },
            set: { newValue in
                switch newValue {
                case .openApp:
                    if case .openApp = action { } else { action = .openApp(bundleID: "") }
                case .keystroke:
                    if case .keystroke = action { } else { action = .keystroke(key: "", modifiers: []) }
                default:
                    action = newValue
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12.5))
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: normalizedActionBinding) {
                    ForEach(GestureAction.allCases, id: \.self) { gestureAction in
                        Text(gestureAction.displayName).tag(gestureAction)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 150)
            }
            if case .keystroke = action {
                KeystrokeField(action: $action)
            }
            if case .openApp(let bundleID) = action {
                AppPickerButton(action: $action, currentBundleID: bundleID)
                    .controlSize(.small)
            }
        }
    }
}

// MARK: - KeystrokeField

/// Inline text field for entering a custom keystroke key.
private struct KeystrokeField: View {
    @Binding var action: GestureAction
    @State private var keyText: String = ""

    var body: some View {
        TextField("key", text: $keyText)
            .frame(width: 60)
            .textFieldStyle(.roundedBorder)
            .onAppear {
                if case .keystroke(let key, _) = action {
                    keyText = key
                }
            }
            .onChange(of: keyText) { newKey in
                // Preserve existing modifiers, just update the key.
                if case .keystroke(_, let modifiers) = action {
                    action = .keystroke(key: newKey, modifiers: modifiers)
                } else {
                    action = .keystroke(key: newKey, modifiers: [])
                }
            }
    }
}

// MARK: - AppPickerButton

/// Button that opens a file panel to pick an app when "Open App…" is selected.
private struct AppPickerButton: View {
    @Binding var action: GestureAction
    let currentBundleID: String

    var body: some View {
        Button(action: openAppPanel) {
            Text(currentBundleID.isEmpty ? "Choose\u{2026}" : shortName(for: currentBundleID))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: 120)
    }

    private func shortName(for bundleID: String) -> String {
        // Show just the last component of the bundle ID for readability.
        // e.g., "com.apple.Safari" → "Safari"
        return bundleID.components(separatedBy: ".").last ?? bundleID
    }

    private func openAppPanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose Application"
        panel.message = "Select the app to open when this gesture fires"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            // Read the bundle ID from the selected .app bundle.
            if let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier {
                action = .openApp(bundleID: bundleID)
            }
        }
    }
}

// MARK: - Preview (for Xcode Previews)

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
#endif
