// UI/Components.swift
// Shared look & building blocks for the panel, quick menu and onboarding.

import AppKit
import SwiftUI

// MARK: - Theme

enum Theme {
    static let accent = Color(red: 0.36, green: 0.35, blue: 0.94)
    static let accentNS = NSColor(srgbRed: 0.36, green: 0.35, blue: 0.94, alpha: 1)
    static let panelWidth: CGFloat = 340

    static func color(for function: EdgeFunction) -> Color {
        switch function {
        case .off: return .secondary
        case .volume: return Color(red: 0.19, green: 0.65, blue: 1.0)
        case .brightness: return Color(red: 1.0, green: 0.62, blue: 0.04)
        case .keyboardBacklight: return Color(red: 0.69, green: 0.45, blue: 1.0)
        case .scroll: return Color(red: 0.2, green: 0.78, blue: 0.55)
        case .zoom: return Color(red: 1.0, green: 0.36, blue: 0.55)
        }
    }

    static func symbol(for family: GestureFamily) -> String {
        switch family {
        case .threeFinger: return "hand.raised.fingers.spread.fill"
        case .fourFinger: return "hand.raised.fill"
        case .cornerForceClick: return "square.dashed.inset.filled"
        case .topEdge: return "arrow.left.and.right.square.fill"
        }
    }

    static func title(for family: GestureFamily) -> String {
        switch family {
        case .threeFinger: return "Three-Finger Tap / Click"
        case .fourFinger: return "Four-Finger Tap / Click"
        case .cornerForceClick: return "Corner Force Click"
        case .topEdge: return "Top Edge Swipe"
        }
    }

    static func subtitle(for family: GestureFamily) -> String {
        switch family {
        case .threeFinger, .fourFinger: return "Quick tap, or hold for a click"
        case .cornerForceClick: return "Press hard in a trackpad corner"
        case .topEdge: return "Flick along the top edge"
        }
    }
}

// MARK: - App icon

/// The app icon, or a drawn stand-in when running unbundled (swift run / tests).
var padletIcon: NSImage {
    if Bundle.main.bundleURL.pathExtension == "app" { return NSApp.applicationIconImage }
    let image = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
        let body = NSBezierPath(roundedRect: rect.insetBy(dx: 4, dy: 4), xRadius: 14, yRadius: 14)
        NSGradient(colors: [NSColor(srgbRed: 0.42, green: 0.42, blue: 1, alpha: 1),
                            NSColor(srgbRed: 0.11, green: 0.10, blue: 0.37, alpha: 1)])?.draw(in: body, angle: -90)
        MenuBarIcon.image(enabled: true).tinted(.white).draw(in: rect.insetBy(dx: 14, dy: 16))
        return true
    }
    return image
}

extension NSImage {
    func tinted(_ color: NSColor) -> NSImage {
        let copy = NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        return copy
    }
}

// MARK: - Building blocks

struct IconBadge: View {
    let symbol: String
    let active: Bool
    var tinted = true
    var color: Color = Theme.accent

    var body: some View {
        let filled = active && tinted
        ZStack {
            Circle().fill(filled ? color : Color.primary.opacity(0.09))
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(filled ? .white : .primary.opacity(0.75))
        }
        .frame(width: 28, height: 28)
        .animation(.easeOut(duration: 0.15), value: filled)
    }
}

struct SwitchToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
    }
}

struct SectionHeader: View {
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
        .padding(.top, 2)
    }
}

struct SettingRow<Trailing: View>: View {
    let icon: String
    let title: String
    let subtitle: String?
    let active: Bool
    var tinted = true
    var color: Color = Theme.accent
    var expanded: Binding<Bool>? = nil
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: icon, active: active, tinted: tinted, color: color)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    if let expanded = expanded {
                        DisclosureChevron(expanded: expanded)
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
            .contentShape(Rectangle())
            .onTapGesture {
                if let expanded = expanded {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.wrappedValue.toggle() }
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

struct DisclosureChevron: View {
    @Binding var expanded: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
                .rotationEffect(.degrees(expanded ? 180 : 0))
                .padding(3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SubRow<Trailing: View>: View {
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

struct SliderRow: View {
    let icon: String
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
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

/// A rounded, softly filled container.
struct Card<Content: View>: View {
    var padding: CGFloat = 10
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.055)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }
}

// MARK: - Action pickers

/// The picker's rows: None, built-ins grouped by category, then the custom actions.
struct ActionMenuItems: View {
    var body: some View {
        Text("None").tag(GestureAction.none)
        ForEach(BuiltinAction.Group.allCases, id: \.self) { group in
            Section(group.rawValue) {
                ForEach(BuiltinAction.cases(in: group), id: \.self) { builtin in
                    Text(builtin.title).tag(GestureAction.builtin(builtin))
                }
            }
        }
        Section("Custom") {
            ForEach(GestureAction.customCases, id: \.self) { Text($0.displayName).tag($0) }
        }
    }
}

/// A gesture label with a compact action picker; extra input (key / app / shortcut) appears below.
struct ActionPickerRow: View {
    let label: String
    @Binding var action: GestureAction
    var pickerWidth: CGFloat = 170

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12.5))
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: Binding(
                    get: { action.pickerValue },
                    set: { action = action.replacing(withPicked: $0) })) {
                    ActionMenuItems()
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: pickerWidth)
            }
            ActionDetailField(action: $action)
        }
    }
}

/// Picker that can also say "use the default" (for app profiles).
struct OverridePickerRow: View {
    let label: String
    let defaultAction: GestureAction
    @Binding var override: GestureAction?
    var pickerWidth: CGFloat = 170

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12.5))
                    .foregroundColor(override == nil ? .secondary : .primary)
                Spacer()
                Picker("", selection: Binding<GestureAction>(
                    get: { override?.pickerValue ?? Self.useDefault },
                    set: { picked in
                        guard picked != Self.useDefault else { override = nil; return }
                        override = (override ?? picked).replacing(withPicked: picked)
                    })) {
                    Text("Default (\(defaultAction.summary))").tag(Self.useDefault)
                    Divider()
                    ActionMenuItems()
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: pickerWidth)
            }
            if override != nil {
                ActionDetailField(action: Binding(get: { override ?? .none }, set: { override = $0 }))
            }
        }
    }

    /// Sentinel tag for "use the default" (an empty shortcut name never reaches storage).
    private static let useDefault = GestureAction.runShortcut(name: "\u{0}default")
}

/// The extra input for Keyboard Shortcut…, Open App… and Run Shortcut… actions.
struct ActionDetailField: View {
    @Binding var action: GestureAction

    var body: some View {
        switch action {
        case .keystroke:
            ShortcutRecorder(action: $action)
        case .openApp(let bundleID):
            AppPickerButton(action: $action, currentBundleID: bundleID).controlSize(.small)
        case .runShortcut(let name):
            ShortcutNameField(action: $action, name: name)
        case .openURL(let url):
            TextField("https://… or app:// link", text: Binding(get: { url }, set: { action = .openURL(url: $0) }))
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(width: 220)
        case .pasteText(let text):
            TextField("Text to paste", text: Binding(get: { text }, set: { action = .pasteText(text: $0) }),
                      axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(width: 220)
        case .runCommand(let command):
            VStack(alignment: .trailing, spacing: 2) {
                TextField("open -a Notes", text: Binding(get: { command }, set: { action = .runCommand(command: $0) }))
                    .font(.system(size: 11, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(width: 220)
                Text("Runs with zsh in your home folder")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        case .builtin(.toggleDoNotDisturb):
            HStack(spacing: 4) {
                Text("Uses the “\(DoNotDisturb.shortcutName)” shortcut")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                Button("Set Up\u{2026}") { DoNotDisturb.showSetupHelp() }
                    .buttonStyle(.link)
                    .font(.system(size: 10.5))
            }
        default:
            EmptyView()
        }
    }
}

/// A keystroke action's recorder.
struct ShortcutRecorder: View {
    @Binding var action: GestureAction

    var body: some View {
        if case .keystroke(let key, let modifiers) = action {
            KeyComboRecorder(combo: Binding(
                get: { key.isEmpty ? nil : KeyCombo(key: key, modifiers: modifiers.rawValue) },
                set: { action = .keystroke(key: $0?.key ?? "", modifiers: $0?.flags ?? []) }))
        }
    }
}

/// Click, then press a key combination. Esc cancels, ⌫ clears.
struct KeyComboRecorder: View {
    @Binding var combo: KeyCombo?
    var placeholder = "Record Shortcut"
    /// Global hotkeys must include ⌘, ⌃ or ⌥ so they don't swallow normal typing.
    var requiresModifier = false
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Type a shortcut\u{2026}" : combo?.display ?? placeholder)
                    .font(.system(size: 12, weight: combo == nil || recording ? .regular : .semibold,
                                  design: combo == nil || recording ? .default : .rounded))
                    .frame(minWidth: 110)
            }
            .controlSize(.small)
            .tint(recording ? Theme.accent : nil)
            .buttonStyle(.bordered)
            .help("Click, then press the keys. Esc cancels.")
            if combo != nil && !recording {
                Button { combo = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        GlobalHotKey.shared.paused = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if mods.isEmpty && event.keyCode == 53 { stop(); return nil }            // Esc
            if mods.isEmpty && event.keyCode == 51 { combo = nil; stop(); return nil } // ⌫
            if requiresModifier && mods.intersection([.command, .control, .option]).isEmpty {
                NSSound.beep()
                return nil
            }
            if let name = KeyCodes.name(for: event.keyCode) {
                combo = KeyCombo(key: name, modifiers: mods.rawValue)
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        GlobalHotKey.shared.paused = false
    }
}

/// A shortcut name with a menu of the shortcuts installed in the Shortcuts app.
struct ShortcutNameField: View {
    @Binding var action: GestureAction
    let name: String
    @State private var available: [String] = []

    var body: some View {
        HStack(spacing: 4) {
            TextField("Shortcut name", text: Binding(get: { name }, set: { action = .runShortcut(name: $0) }))
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)
            Menu {
                if available.isEmpty { Text("No shortcuts found") }
                ForEach(available, id: \.self) { item in
                    Button(item) { action = .runShortcut(name: item) }
                }
                Divider()
                Button("Open Shortcuts") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
                }
            } label: {
                Image(systemName: "list.bullet")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Choose from your shortcuts")
        }
        .controlSize(.small)
        .onAppear { ShortcutsLibrary.load { available = $0 } }
    }
}

/// Names of the user's shortcuts, read once via `shortcuts list`.
enum ShortcutsLibrary {
    private static var cache: [String]?

    static func load(_ completion: @escaping ([String]) -> Void) {
        if let cache { completion(cache); return }
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            task.arguments = ["list"]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice
            var names: [String] = []
            if (try? task.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                names = String(decoding: data, as: UTF8.self)
                    .split(separator: "\n").map(String.init).filter { !$0.isEmpty }.sorted()
            }
            DispatchQueue.main.async {
                cache = names
                completion(names)
            }
        }
    }
}

struct AppPickerButton: View {
    @Binding var action: GestureAction
    let currentBundleID: String

    var body: some View {
        Button { chooseApp { action = .openApp(bundleID: $0.bundleID) } } label: {
            Text(currentBundleID.isEmpty ? "Choose App\u{2026}" : AppInfo(bundleID: currentBundleID).name)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: 160)
    }
}

// MARK: - Apps

struct AppInfo {
    let bundleID: String
    let name: String
    let url: URL?

    init(bundleID: String, name: String? = nil) {
        self.bundleID = bundleID
        url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        self.name = name
            ?? url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
            ?? bundleID.components(separatedBy: ".").last
            ?? bundleID
    }

    var icon: NSImage {
        guard let url = url else { return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage() }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// Shows an Open panel for an .app and returns its info.
func chooseApp(_ completion: @escaping (AppInfo) -> Void) {
    let panel = NSOpenPanel()
    panel.title = "Choose an App"
    panel.allowedContentTypes = [.applicationBundle]
    panel.allowsMultipleSelection = false
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    NSApp.activate(ignoringOtherApps: true)
    panel.begin { response in
        guard response == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        completion(AppInfo(bundleID: bundleID, name: name))
    }
}

func openAccessibilitySettings() {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
}
