// App/AppDelegate.swift
// Launch sequence:
//   1. Event taps (click suppressor, cursor freezer) and the menu bar item.
//   2. First launch: turn on Open at Login and show the welcome window, which asks for
//      Accessibility itself. Later launches: prompt for Accessibility only if missing.
//   3. Start the gesture engine as soon as Accessibility is granted.
// Also restarts the engine around sleep/wake (device handles and event taps go stale).

import AppKit
import ApplicationServices
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var menuBarController: MenuBarController!
    private let permissionsManager = PermissionsManager()
    private var onboarding: OnboardingWindowController?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if PanelSnapshot.runIfRequested() { return }
        #endif

        _ = ClickSuppressor.shared
        _ = CursorFreezer.shared

        followAppearanceSetting()
        AppMenu.install(target: self)
        menuBarController = MenuBarController()
        menuBarController.onShowWelcome = { [weak self] in self?.showOnboarding() }
        UpdateManager.shared.startAutomaticChecks()
        applyOpenAtLoginDefault()

        if !Preferences.shared.general.onboardingCompleted {
            showOnboarding()
        } else if !PermissionsManager.isAccessibilityGranted() {
            permissionsManager.requestAccessibilityPermission()
        }

        if PermissionsManager.isAccessibilityGranted() {
            GestureCoordinator.shared.start()
        } else {
            menuBarController.showPermissionWarning()
            permissionsManager.pollUntilGranted { [weak self] in
                self?.menuBarController.hidePermissionWarning()
                ClickSuppressor.shared.reinstall()   // taps created before the grant are inert
                CursorFreezer.shared.reinstall()
                GestureCoordinator.shared.start()
            }
        }

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(machineWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(machineDidWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        GestureCoordinator.shared.stop()
        CursorFreezer.shared.release()
    }

    // MARK: - App menu actions

    @objc func showAbout(_ sender: Any?) { AppWindows.shared.showAbout() }

    @objc func showSettings(_ sender: Any?) { AppWindows.shared.showSettings() }

    @objc func showWelcome(_ sender: Any?) { showOnboarding() }

    @objc func checkForUpdates(_ sender: Any?) {
        UpdateManager.shared.check(userInitiated: true)
        AppWindows.shared.showAbout()
    }

    // MARK: - Onboarding

    func showOnboarding() {
        if onboarding == nil {
            onboarding = OnboardingWindowController { [weak self] in
                Preferences.shared.general.onboardingCompleted = true
                self?.onboarding = nil
            }
        }
        onboarding?.show()
    }

    // MARK: - Settings side effects

    private func followAppearanceSetting() {
        Preferences.shared.$general
            .map(\.appearance)
            .removeDuplicates()
            .sink { mode in
                switch mode {
                case .system: NSApp.appearance = nil
                case .light:  NSApp.appearance = NSAppearance(named: .aqua)
                case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
                }
            }
            .store(in: &cancellables)
    }

    /// Open at Login defaults to on: registered once on first launch, then left to the user.
    private func applyOpenAtLoginDefault() {
        let prefs = Preferences.shared
        guard !prefs.general.openAtLoginDefaultApplied else { return }
        if Bundle.main.bundleURL.pathExtension == "app" {
            if let error = LaunchAtLogin.set(true) { Log.error("Open at Login: \(error)") }
        }
        prefs.general.openAtLoginDefaultApplied = true
    }

    // MARK: - Sleep / wake

    @objc private func machineWillSleep(_ note: Notification) {
        GestureCoordinator.shared.stop()
    }

    @objc private func machineDidWake(_ note: Notification) {
        // Give HID services a moment before re-enumerating devices.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard PermissionsManager.isAccessibilityGranted() else { return }
            ClickSuppressor.shared.reinstall()
            CursorFreezer.shared.reinstall()
            GestureCoordinator.shared.start()
        }
    }
}
