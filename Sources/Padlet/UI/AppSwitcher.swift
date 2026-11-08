// UI/AppSwitcher.swift
// The top-edge app switcher: a floating strip of app icons (most recent first) that the
// finger scrubs through; lifting the finger activates the selection, like releasing ⌘⇥.
//
// Driven by EdgeActionPerformer on the main thread:
//   begin() (snapshot apps, nothing shown) → select(offset:) (first one shows the strip) … → end(commit:)
// Offset 0 is the frontmost app; offsets wrap around both ways.

import AppKit
import SwiftUI

struct SwitcherItem: Identifiable {
    let id: pid_t
    let name: String
    let icon: NSImage
}

final class AppSwitcherModel: ObservableObject {
    @Published var items: [SwitcherItem] = []
    @Published var selected = 0
    @Published var iconSize: CGFloat = AppSwitcherView.maxIconSize
}

final class AppSwitcher {

    static let shared = AppSwitcher()

    private let model = AppSwitcherModel()
    private var apps: [NSRunningApplication] = []
    private var panel: NSPanel?

    var isOpen: Bool { panel?.isVisible == true }
    var windowNumber: Int? { panel?.windowNumber }

    func begin() {
        apps = FrontmostAppTracker.shared.switcherApps()
        guard apps.count > 1 else { apps = []; return }
        model.items = apps.map {
            SwitcherItem(id: $0.processIdentifier, name: $0.localizedName ?? "App",
                         icon: $0.icon ?? NSWorkspace.shared.icon(for: .application))
        }
        model.selected = 0
    }

    func select(offset: Int) {
        guard !apps.isEmpty else { return }
        let n = apps.count
        model.selected = ((offset % n) + n) % n
        if !isOpen { show() }
    }

    func end(commit: Bool) {
        defer {
            panel?.orderOut(nil)
            apps = []
        }
        guard commit, isOpen, apps.indices.contains(model.selected) else { return }
        let target = apps[model.selected]
        guard !target.isTerminated,
              target.processIdentifier != NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        if target.isHidden { target.unhide() }
        if #available(macOS 14.0, *) {
            target.activate()
        } else {
            target.activate(options: [.activateIgnoringOtherApps])
        }
        Log.info("App switcher → \(target.localizedName ?? "?")")
    }

    // MARK: Panel

    private func show() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        model.iconSize = AppSwitcherView.iconSize(count: apps.count, maxWidth: visible.width - 80)

        let panel = self.panel ?? makePanel()
        self.panel = panel
        let hosting = NSHostingView(rootView: AppSwitcherView(model: model))
        panel.contentView = hosting
        let size = hosting.fittingSize
        panel.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }
}

// MARK: - View

struct AppSwitcherView: View {
    @ObservedObject var model: AppSwitcherModel
    /// Snapshots turn glass off: it doesn't render offscreen.
    var useGlass = true

    static let maxIconSize: CGFloat = 64
    static let minIconSize: CGFloat = 32
    static let spacing: CGFloat = 8
    static let cellPadding: CGFloat = 8
    static let outerPadding: CGFloat = 16
    static let outerRadius: CGFloat = 24

    /// Shrinks the icons so `count` of them fit in `maxWidth`.
    static func iconSize(count: Int, maxWidth: CGFloat) -> CGFloat {
        guard count > 0 else { return maxIconSize }
        let perCell = (maxWidth - 2 * outerPadding + spacing) / CGFloat(count) - spacing
        return min(maxIconSize, max(minIconSize, (perCell - 2 * cellPadding).rounded(.down)))
    }

    var body: some View {
        let cellRadius = Self.outerRadius - Self.outerPadding + Self.cellPadding
        VStack(spacing: 8) {
            HStack(spacing: Self.spacing) {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    Image(nsImage: item.icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: model.iconSize, height: model.iconSize)
                        .padding(Self.cellPadding)
                        .background(
                            RoundedRectangle(cornerRadius: cellRadius, style: .continuous)
                                .fill(Color.primary.opacity(index == model.selected ? 0.16 : 0))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: cellRadius, style: .continuous)
                                .strokeBorder(Color.primary.opacity(index == model.selected ? 0.22 : 0), lineWidth: 1)
                        )
                        .accessibilityLabel(item.name)
                }
            }
            Text(model.items.indices.contains(model.selected) ? model.items[model.selected].name : "")
                .font(.headline)
                .foregroundStyle(Color(nsColor: .labelColor))
                .lineLimit(1)
        }
        .padding(Self.outerPadding)
        .modifier(SwitcherBackground(radius: Self.outerRadius, useGlass: useGlass))
        .animation(Self.reduceMotion ? nil : .easeOut(duration: 0.12), value: model.selected)
    }

    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

/// Liquid Glass on macOS 26, a HUD material before that.
private struct SwitcherBackground: ViewModifier {
    let radius: CGFloat
    let useGlass: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(macOS 26.0, *), useGlass, !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        }
    }
}
