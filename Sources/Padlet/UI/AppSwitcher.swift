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
    private var screenObserver: NSObjectProtocol?

    init() {
        // Plugging/unplugging displays can leave a reused panel tied to a display that no longer
        // exists, so it never shows again. Throw it away; the next gesture builds a fresh one.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.discardPanel() }
    }

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

    private func show(retry: Bool = true) {
        let screen = Self.targetScreen(mouse: NSEvent.mouseLocation, screens: NSScreen.screens)
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        model.iconSize = AppSwitcherView.iconSize(count: apps.count, maxWidth: visible.width - 80)

        let panel = self.panel ?? makePanel()
        self.panel = panel
        let hosting = NSHostingView(rootView: AppSwitcherView(
            model: model, background: Preferences.shared.edge.switcherBackground))
        panel.contentView = hosting
        let size = hosting.fittingSize
        panel.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()

        // A panel left over from an old display layout can refuse to come up: rebuild it once.
        if retry, !panel.isVisible || panel.screen == nil {
            Log.info("App switcher panel didn't show, rebuilding")
            discardPanel()
            show(retry: false)
        }
    }

    private func discardPanel() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }

    /// The display under the pointer; when the pointer sits on no display (a gap between
    /// displays, or the outer edge) the nearest one; with no displays reported, nil.
    /// `screens.first` is the primary display (menu bar), the fallback when nothing is near.
    static func targetScreen(mouse: NSPoint, screens: [NSScreen]) -> NSScreen? {
        guard let i = targetIndex(mouse: mouse, frames: screens.map(\.frame)) else { return nil }
        return screens[i]
    }

    static func targetIndex(mouse: NSPoint, frames: [NSRect]) -> Int? {
        guard !frames.isEmpty else { return nil }
        if let i = frames.firstIndex(where: { NSMouseInRect(mouse, $0, false) }) { return i }
        func distance(_ r: NSRect) -> CGFloat {
            let dx = max(r.minX - mouse.x, 0, mouse.x - r.maxX)
            let dy = max(r.minY - mouse.y, 0, mouse.y - r.maxY)
            return dx * dx + dy * dy
        }
        return frames.indices.min { distance(frames[$0]) < distance(frames[$1]) }
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
    /// Snapshots use `.blur`: glass doesn't render offscreen.
    var background: SwitcherBackgroundStyle = .liquidGlass

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
        .modifier(SwitcherBackground(radius: Self.outerRadius, style: background))
        .animation(Self.reduceMotion ? nil : .easeOut(duration: 0.12), value: model.selected)
    }

    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

/// Liquid Glass (macOS 26, Reduce Transparency off) or a blurred material.
private struct SwitcherBackground: ViewModifier {
    let radius: CGFloat
    let style: SwitcherBackgroundStyle

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(macOS 26.0, *), style == .liquidGlass, !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        }
    }
}
