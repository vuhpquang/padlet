// App/MenuBarController.swift
// The menu bar item.
//   • Left click  → the Padlet panel (popover hosting PanelView).
//   • Right click → quick menu: header + family switches (SwiftUI), then commands.
// The glyph shows a slash when everything is off and turns orange without Accessibility.

import AppKit
import Combine
import SwiftUI

final class MenuBarController: NSObject {

    var onShowWelcome: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let popover = NSPopover()
    private var accessibilityWarningItem: NSMenuItem?
    private var permissionMissing = false
    private var cancellables: Set<AnyCancellable> = []

    override init() {
        super.init()
        setupButton()
        setupPopover()
        setupMenu()

        Preferences.shared.$flags
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.render(enabled: $0.masterEnabled) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .padletShowSettingsWindow)
            .sink { [weak self] _ in
                self?.popover.performClose(nil)
                AppWindows.shared.showSettings()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .padletShowAbout)
            .sink { [weak self] _ in
                self?.popover.performClose(nil)
                AppWindows.shared.showAbout()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .padletShowWelcome)
            .sink { [weak self] _ in
                self?.popover.performClose(nil)
                self?.onShowWelcome?()
            }
            .store(in: &cancellables)
    }

    // MARK: - Setup

    private func setupButton() {
        guard let button = statusItem.button else { return }
        button.image = MenuBarIcon.image(enabled: true)
        button.action = #selector(statusItemClicked(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setupPopover() {
        let hosting = NSHostingController(rootView: PanelView())
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true
    }

    private func setupMenu() {
        let header = NSMenuItem()
        let hosting = NSHostingView(rootView: QuickMenuView())
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        header.view = hosting
        menu.addItem(header)
        menu.addItem(.separator())

        addItem("Open Padlet", symbol: "rectangle.on.rectangle", key: "o") { [weak self] in self?.showPanel(.main) }
        addItem("App Profiles\u{2026}", symbol: "square.stack.3d.up", key: "p") { AppWindows.shared.showSettings(.profiles) }
        addItem("Settings\u{2026}", symbol: "gearshape", key: ",") { AppWindows.shared.showSettings() }
        menu.addItem(.separator())
        addItem("About Padlet", symbol: "info.circle") { AppWindows.shared.showAbout() }
        addItem("Check for Updates\u{2026}", symbol: "arrow.triangle.2.circlepath") {
            UpdateManager.shared.check(userInitiated: true)
            AppWindows.shared.showAbout()
        }
        addItem("Welcome Guide\u{2026}", symbol: "sparkles") { [weak self] in self?.onShowWelcome?() }
        menu.addItem(.separator())
        addItem("Quit Padlet", symbol: "power", key: "q") { NSApp.terminate(nil) }
    }

    private var handlers: [NSMenuItem: () -> Void] = [:]

    @discardableResult
    private func addItem(_ title: String, symbol: String, key: String = "", at index: Int? = nil,
                         _ handler: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(runHandler(_:)), keyEquivalent: key)
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        handlers[item] = handler
        if let index = index { menu.insertItem(item, at: index) } else { menu.addItem(item) }
        return item
    }

    @objc private func runHandler(_ sender: NSMenuItem) {
        handlers[sender]?()
    }

    // MARK: - Clicks

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            popover.performClose(nil)
            statusItem.menu = menu        // attach just long enough to pop it up
            sender.performClick(nil)
            statusItem.menu = nil
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            showPanel(nil)
        }
    }

    /// Opens the panel, optionally on a given page.
    func showPanel(_ page: PanelPage?) {
        if let page = page { PanelRouter.shared.page = page }
        guard let button = statusItem.button else { return }
        if !popover.isShown {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Icon

    private func render(enabled: Bool) {
        guard let button = statusItem.button else { return }
        button.image = MenuBarIcon.image(enabled: enabled)
        button.appearsDisabled = !enabled
        button.contentTintColor = permissionMissing ? .systemOrange : nil
        button.toolTip = enabled
            ? "Padlet — click for controls, right-click for quick switches"
            : "Padlet — all gestures are off"
    }

    // MARK: - Permission warning

    func showPermissionWarning() {
        guard accessibilityWarningItem == nil else { return }
        permissionMissing = true
        statusItem.button?.contentTintColor = .systemOrange
        let item = addItem("Enable Accessibility\u{2026}", symbol: "exclamationmark.triangle.fill", at: 2) {
            openAccessibilitySettings()
        }
        menu.insertItem(.separator(), at: 3)
        accessibilityWarningItem = item
    }

    func hidePermissionWarning() {
        guard let item = accessibilityWarningItem else { return }
        if let index = menu.items.firstIndex(of: item) {
            menu.removeItem(at: index)
            if index < menu.items.count && menu.items[index].isSeparatorItem { menu.removeItem(at: index) }
        }
        handlers[item] = nil
        accessibilityWarningItem = nil
        permissionMissing = false
        statusItem.button?.contentTintColor = nil
    }
}
