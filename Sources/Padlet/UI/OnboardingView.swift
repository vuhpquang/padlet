// UI/OnboardingView.swift
// First-launch welcome: 1) what Padlet does  2) Accessibility permission (watched live,
// advances by itself once granted)  3) try an edge slide, with a live readout.

import AppKit
import Combine
import SwiftUI

// MARK: - Window

final class OnboardingWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func show() {
        if window == nil {
            let view = OnboardingView { [weak self] in self?.close() }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.contentView = NSHostingView(rootView: view)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        onFinish()
    }
}

// MARK: - View

struct OnboardingView: View {
    let finish: () -> Void
    @State var step = 0

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: WelcomeStep()
                case 1: PermissionStep(onGranted: { advance(to: 2) })
                default: TryItStep()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))

            HStack {
                if step > 0 {
                    Button("Back") { advance(to: step - 1) }
                        .buttonStyle(.borderless)
                }
                Spacer()
                HStack(spacing: 7) {
                    ForEach(0..<3) { i in
                        Capsule()
                            .fill(i == step ? Theme.accent : Color.primary.opacity(0.15))
                            .frame(width: i == step ? 18 : 7, height: 7)
                    }
                }
                Spacer()
                Button(step == 2 ? "Done" : "Continue") {
                    if step == 2 { finish() } else { advance(to: step + 1) }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 22)
        }
        .frame(width: 560, height: 470)
        .tint(Theme.accent)
        .background(
            LinearGradient(colors: [Theme.accent.opacity(0.10), Color.clear],
                           startPoint: .top, endPoint: .center)
        )
    }

    private func advance(to newStep: Int) {
        withAnimation(.easeInOut(duration: 0.25)) { step = min(max(newStep, 0), 2) }
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: padletIcon)
                .resizable()
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                .padding(.top, 34)
            VStack(spacing: 6) {
                Text("Welcome to Padlet")
                    .font(.system(size: 28, weight: .bold))
                Text("Your trackpad, with a few more tricks.")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 12) {
                FeatureTile(symbol: "rectangle.portrait.lefthalf.inset.filled", color: Theme.color(for: .volume),
                            title: "Edge Controls", text: "Slide along an edge for volume or brightness.")
                FeatureTile(symbol: "hand.raised.fingers.spread.fill", color: Theme.accent,
                            title: "Gestures", text: "Three- and four-finger taps, force-click corners.")
                FeatureTile(symbol: "square.stack.3d.up.fill", color: Theme.color(for: .zoom),
                            title: "App Profiles", text: "Different actions in different apps.")
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            Spacer()
        }
    }
}

private struct FeatureTile: View {
    let symbol: String
    let color: Color
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 24, height: 22, alignment: .leading)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

// MARK: - Step 2: Permission

private struct PermissionStep: View {
    let onGranted: () -> Void
    @State private var granted = PermissionsManager.isAccessibilityGranted()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(granted ? Color.green.opacity(0.15) : Theme.accent.opacity(0.13))
                    .frame(width: 96, height: 96)
                Image(systemName: granted ? "checkmark.shield.fill" : "hand.raised.square.on.square.fill")
                    .font(.system(size: 42))
                    .foregroundColor(granted ? .green : Theme.accent)
            }
            .padding(.top, 34)

            VStack(spacing: 8) {
                Text(granted ? "You're all set" : "Allow Padlet to use your trackpad")
                    .font(.system(size: 22, weight: .bold))
                Text(granted
                     ? "Accessibility access is on. Padlet is listening for gestures."
                     : "Padlet needs Accessibility access to read gestures and to send clicks, shortcuts and media keys. It never sees your screen or what you type.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !granted {
                VStack(alignment: .leading, spacing: 8) {
                    StepLine(n: 1, text: "Click **Open System Settings**")
                    StepLine(n: 2, text: "Turn on **Padlet** under Accessibility")
                    StepLine(n: 3, text: "Come back — this page updates by itself")
                }
                .padding(.top, 4)

                Button {
                    PermissionsManager().requestAccessibilityPermission()
                    openAccessibilitySettings()
                } label: {
                    Label("Open System Settings", systemImage: "gearshape")
                }
                .controlSize(.large)
            }
            Spacer()
        }
        .padding(.horizontal, 28)
        .onReceive(timer) { _ in
            let now = PermissionsManager.isAccessibilityGranted()
            if now && !granted {
                withAnimation { granted = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: onGranted)
            }
        }
    }
}

private struct StepLine: View {
    let n: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: 10) {
            Text("\(n)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.accent))
            Text(text).font(.system(size: 13))
        }
    }
}

// MARK: - Step 3: Try it

private final class EdgeActivityWatcher: ObservableObject {
    @Published var lastFunction: EdgeFunction?
    @Published var lastValue: Float?
    private var cancellable: AnyCancellable?

    init() {
        cancellable = NotificationCenter.default.publisher(for: .padletEdgeActivity)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                self?.lastFunction = note.userInfo?["function"] as? EdgeFunction
                self?.lastValue = note.userInfo?["value"] as? Float
            }
    }
}

private struct TryItStep: View {
    @ObservedObject private var prefs = Preferences.shared
    @StateObject private var watcher = EdgeActivityWatcher()

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Text("Try it")
                    .font(.system(size: 26, weight: .bold))
                Text("Slide one finger up or down along the \(edgeHint).")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                if prefs.edge.requireModifier {
                    Label("Hold Fn or ⌥ while you slide — you turned that on", systemImage: "option")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.orange)
                }
            }
            .padding(.top, 30)

            TrackpadIllustration(left: prefs.edge.leftFunction, right: prefs.edge.rightFunction,
                                 active: watcher.lastFunction)
                .frame(width: 300, height: 190)

            Group {
                if let f = watcher.lastFunction {
                    Label(feedback(f), systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Label("Waiting for your first slide\u{2026}", systemImage: "hand.point.up.left")
                        .foregroundColor(.secondary)
                }
            }
            .font(.system(size: 13, weight: .medium))
            .animation(.easeOut, value: watcher.lastFunction)

            Text("Also: double-tap the top-right corner to mute · swipe the bottom edge to skip songs · everything lives in the menu bar.")
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private var edgeHint: String {
        let l = prefs.edge.leftFunction, r = prefs.edge.rightFunction
        switch (l == .off, r == .off) {
        case (false, false): return "right edge (\(r.title.lowercased())) or left edge (\(l.title.lowercased()))"
        case (true, false): return "right edge (\(r.title.lowercased()))"
        case (false, true): return "left edge (\(l.title.lowercased()))"
        case (true, true): return "trackpad edge (turn an edge on in the menu bar panel first)"
        }
    }

    private func feedback(_ f: EdgeFunction) -> String {
        if let v = watcher.lastValue { return "Nice! \(f.title) \(Int((v * 100).rounded()))%" }
        return "Nice! \(f.title) changed"
    }
}

/// A trackpad drawing with a fingertip gliding up and down each active edge.
struct TrackpadIllustration: View {
    let left: EdgeFunction
    let right: EdgeFunction
    var active: EdgeFunction?

    @State private var phase = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1.5)

                strip(left, x: 14, h: h)
                strip(right, x: w - 14, h: h)

                if left != .off { finger(x: 14, h: h, reversed: true) }
                if right != .off { finger(x: w - 14, h: h, reversed: false) }

                // Quick-mute corner + media strip hints
                Circle().strokeBorder(Color.red.opacity(0.6), lineWidth: 1.5)
                    .frame(width: 14, height: 14)
                    .position(x: w - 22, y: 20)
                Capsule().fill(Color.pink.opacity(0.35))
                    .frame(width: w * 0.45, height: 5)
                    .position(x: w / 2, y: h - 10)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { phase = true }
        }
    }

    private func strip(_ f: EdgeFunction, x: CGFloat, h: CGFloat) -> some View {
        let color = Theme.color(for: f)
        let lit = active == f
        return Capsule()
            .fill(f == .off ? Color.primary.opacity(0.08) : color.opacity(lit ? 0.95 : 0.55))
            .frame(width: 6, height: h - 50)
            .shadow(color: lit ? color : .clear, radius: 8)
            .position(x: x, y: h / 2)
            .overlay(
                Image(systemName: f.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(f == .off ? .secondary : color)
                    .position(x: x < 50 ? x + 22 : x - 22, y: h / 2)
            )
    }

    private func finger(x: CGFloat, h: CGFloat, reversed: Bool) -> some View {
        let top = 40.0, bottom = h - 40
        let up = phase != reversed
        return Circle()
            .fill(Color.primary.opacity(0.22))
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.35), lineWidth: 1))
            .frame(width: 22, height: 22)
            .position(x: x, y: up ? top : bottom)
    }
}
