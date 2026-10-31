// MenuBarController.swift
// The menu bar item.
//   • Left click  → the Mac Shortcuts panel (a popover hosting SettingsView).
//   • Right click → a compact menu: master switch, per-family switches, Settings…, Quit.
// The glyph (MenuBarIcon) shows a slash when everything is off and turns amber when
// Accessibility permission is missing.

import AppKit
import Combine
import SwiftUI

class MenuBarController: NSObject {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let popover = NSPopover()

    private var masterItem: NSMenuItem?
    private var familyItems: [(NSMenuItem, WritableKeyPath<FeatureFlags, Bool>)] = []
    private var accessibilityWarningItem: NSMenuItem?
    private var cancellables: Set<AnyCancellable> = []
    private var permissionMissing = false

    override init() {
        super.init()
        setupButton()
        setupPopover()
        setupMenu()

        Preferences.shared.$flags
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.render(flags: $0) }
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
        let hosting = NSHostingController(rootView: SettingsView())
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true
    }

    private func setupMenu() {
        let master = NSMenuItem(title: "Enable Mac Shortcuts", action: #selector(toggleMaster), keyEquivalent: "e")
        master.target = self
        menu.addItem(master)
        masterItem = master

        let families: [(String, WritableKeyPath<FeatureFlags, Bool>)] = [
            ("Three-Finger Tap / Click", \.threeFinger),
            ("Corner Force Click", \.cornerForceClick),
            ("Edge Controls", \.edgeControls),
        ]
        for (title, keyPath) in families {
            let item = NSMenuItem(title: title, action: #selector(toggleFamily(_:)), keyEquivalent: "")
            item.target = self
            item.indentationLevel = 1
            menu.addItem(item)
            familyItems.append((item, keyPath))
        }

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings\u{2026}", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let update = NSMenuItem(title: "Check for Updates\u{2026}", action: #selector(checkForUpdates), keyEquivalent: "")
        update.target = self
        menu.addItem(update)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Mac Shortcuts", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - Click handling

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || (event?.modifierFlags.contains(.control) ?? false)
        if isRightClick {
            popover.performClose(nil)
            statusItem.menu = menu           // attach just long enough to pop it up
            sender.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Actions

    @objc private func toggleMaster() {
        Preferences.shared.flags.masterEnabled.toggle()
    }

    @objc private func toggleFamily(_ sender: NSMenuItem) {
        guard let keyPath = familyItems.first(where: { $0.0 === sender })?.1 else { return }
        Preferences.shared.flags[keyPath: keyPath].toggle()
    }

    /// Opens the panel on its Settings page.
    @objc func openSettings() {
        if !popover.isShown { togglePopover() }
        NotificationCenter.default.post(name: .showSettingsPage, object: nil)
    }

    @objc private func checkForUpdates() {
        UpdateManager.shared.check(userInitiated: true)
        if !popover.isShown { togglePopover() }
        NotificationCenter.default.post(name: .showSettingsPage, object: nil)
    }

    @objc private func openAccessibility() {
        openAccessibilitySettings()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Rendering

    private func render(flags: FeatureFlags) {
        masterItem?.state = flags.masterEnabled ? .on : .off
        for (item, keyPath) in familyItems {
            item.state = flags[keyPath: keyPath] ? .on : .off
            item.isEnabled = flags.masterEnabled
        }
        guard let button = statusItem.button else { return }
        button.image = MenuBarIcon.image(enabled: flags.masterEnabled)
        button.appearsDisabled = !flags.masterEnabled
        button.contentTintColor = permissionMissing ? .systemOrange : nil
        button.toolTip = flags.masterEnabled
            ? "Mac Shortcuts — click for controls, right-click for quick switches"
            : "Mac Shortcuts — all gestures are off"
    }

    // MARK: - Permission warning

    func showPermissionWarning() {
        guard accessibilityWarningItem == nil else { return }
        permissionMissing = true
        statusItem.button?.contentTintColor = .systemOrange

        let item = NSMenuItem(title: "Enable Accessibility\u{2026}", action: #selector(openAccessibility), keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Warning")
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
        accessibilityWarningItem = item
    }

    func hidePermissionWarning() {
        guard let item = accessibilityWarningItem else { return }
        if let index = menu.items.firstIndex(of: item) {
            menu.removeItem(at: index)
            if index < menu.items.count && menu.items[index].isSeparatorItem {
                menu.removeItem(at: index)
            }
        }
        accessibilityWarningItem = nil
        permissionMissing = false
        statusItem.button?.contentTintColor = nil
    }
}
