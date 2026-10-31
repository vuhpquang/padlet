// Core/GestureCoordinator.swift
// This file is the central hub that connects all the pieces of GestureKit together.
//
// Think of it as an air traffic controller:
//   • DeviceMonitor sends raw finger data → GestureCoordinator (here)
//   • GestureCoordinator fans each frame out to the enabled recognizers:
//       – GestureRecognizer      (three-finger tap/click, corner force click)
//       – EdgeGestureRecognizer  (volume/brightness edges, quick mute, media strip)
//   • GestureRecognizer reports gestures back here → ActionExecutor runs the mapped action
//
// It also owns the on/off switches (Preferences.flags). The master switch stops the
// multitouch listener entirely; the per-family switches stop that recognizer's state
// machine, so a disabled family can't affect anything (not even click suppression).
//
// GestureCoordinator is a singleton. AppDelegate calls start()/stop() for lifecycle
// (permission granted, sleep/wake, quit); the user's switches decide whether a started
// engine is actually listening.

import AppKit
import Combine
import Foundation

// MARK: - GestureCoordinator Singleton

class GestureCoordinator: GestureRecognizerDelegate, DeviceMonitorDelegate {

    // MARK: - Singleton

    /// The single shared instance. Use GestureCoordinator.shared everywhere.
    static let shared = GestureCoordinator()

    // MARK: - Owned Components

    /// Listens to the trackpad hardware and delivers raw finger data.
    private let deviceMonitor = DeviceMonitor()

    /// Three-finger + force-click-corner recognizer.
    private let gestureRecognizer = GestureRecognizer()

    /// Trackpad edge controls.
    private let edgeRecognizer = EdgeGestureRecognizer()

    // MARK: - State

    /// The current gesture→action mapping. Updated by SettingsView when the user changes settings.
    private var mapping: GestureMapping = .defaults

    /// Snapshot of the feature switches, read on the multitouch thread.
    private let flagsLock = NSLock()
    private var _flags = FeatureFlags()
    private var flags: FeatureFlags {
        get { flagsLock.lock(); defer { flagsLock.unlock() }; return _flags }
        set { flagsLock.lock(); _flags = newValue; flagsLock.unlock() }
    }

    /// Lifecycle wants the engine running (permission granted, machine awake).
    private var wantsRunning = false

    /// Whether the multitouch listener is currently running.
    var isRunning: Bool { deviceMonitor.isRunning }

    private var cancellables: Set<AnyCancellable> = []
    private var keyMonitor: Any?

    // MARK: - Initialization

    private init() {
        deviceMonitor.delegate = self
        gestureRecognizer.delegate = self

        let prefs = Preferences.shared
        prefs.$flags
            .removeDuplicates()
            .sink { [weak self] in self?.apply(flags: $0) }
            .store(in: &cancellables)
        prefs.$edge
            .removeDuplicates()
            .sink { [weak self] in self?.edgeRecognizer.settings = $0 }
            .store(in: &cancellables)
        prefs.$mapping
            .removeDuplicates()
            .sink { [weak self] in self?.updateMapping($0) }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    /// Lifecycle: the engine may run (Accessibility granted / machine woke).
    /// It actually listens only if the master switch is on.
    func start() {
        wantsRunning = true
        refreshRunningState()
    }

    /// Lifecycle: the engine must stop (sleep / quit).
    func stop() {
        wantsRunning = false
        refreshRunningState()
    }

    private func refreshRunningState() {
        let shouldRun = wantsRunning && flags.masterEnabled
        if shouldRun && !deviceMonitor.isRunning {
            deviceMonitor.start()
            installKeyMonitor()
            print("[MacShortcuts] GestureCoordinator: Started.")
        } else if !shouldRun && deviceMonitor.isRunning {
            deviceMonitor.stop()
            removeKeyMonitor()
            CursorFreezer.shared.release()
            print("[MacShortcuts] GestureCoordinator: Stopped.")
        }
    }

    // MARK: - Switches

    private func apply(flags newFlags: FeatureFlags) {
        flags = newFlags
        gestureRecognizer.threeFingerEnabled = newFlags.threeFinger
        gestureRecognizer.forceClickEnabled = newFlags.cornerForceClick
        if !newFlags.edgeControls { CursorFreezer.shared.release() }
        refreshRunningState()
        print("[MacShortcuts] GestureCoordinator: flags = \(newFlags)")
    }

    // MARK: - Typing guard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            self?.edgeRecognizer.noteKeyPress()
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        keyMonitor = nil
    }

    // MARK: - Mapping Hot-Swap

    /// Updates the active gesture→action mapping without restarting the pipeline.
    /// Called by SettingsView whenever the user changes a gesture's assigned action,
    /// so changes take effect immediately without requiring a restart.
    func updateMapping(_ newMapping: GestureMapping) {
        mapping = newMapping
        print("[MacShortcuts] GestureCoordinator: Mapping updated.")
    }

    // MARK: - DeviceMonitorDelegate (multitouch thread)

    func didReceiveFingers(_ fingers: [MTFinger], timestamp: Double, fromMouse: Bool) {
        let f = flags
        guard f.masterEnabled else { return }
        if f.threeFinger || f.cornerForceClick {
            gestureRecognizer.process(fingers: fingers, timestamp: timestamp)
        }
        // Edge controls are a trackpad feature — a Magic Mouse surface has no "edges" to slide.
        if f.edgeControls && !fromMouse {
            edgeRecognizer.process(fingers: fingers, timestamp: timestamp)
        }
    }

    // MARK: - GestureRecognizerDelegate

    /// Called by GestureRecognizer whenever a gesture is recognized.
    /// Looks up the corresponding action in the current mapping and executes it.
    func didRecognize(gesture: GestureEvent) {
        let f = flags
        guard f.masterEnabled else { return }
        switch gesture {
        case .threeFingerTap, .threeFingerClick:
            guard f.threeFinger else { return }
        case .forceClickCorner:
            guard f.cornerForceClick else { return }
        }

        let action = mapping.action(for: gesture)

        // Skip if this gesture slot is unmapped (action = .none).
        guard action != .none else { return }

        print("[MacShortcuts] GestureCoordinator: Gesture \(gesture) → Action \(action.displayName)")

        // Some actions (like opening a window) need to run on the main thread.
        // We dispatch everything to main to be safe — CGEvents work from any thread,
        // but NSWorkspace and UI calls require main.
        DispatchQueue.main.async {
            ActionExecutor.shared.execute(action)
        }
    }
}
