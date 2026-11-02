// Engine/GestureCoordinator.swift
// Wires the pipeline together and owns the on/off logic:
//
//   DeviceMonitor ──frames──▶ FingerGestureRecognizer ──FingerEvent──┐
//        (multitouch thread)  EdgeGestureRecognizer   ──EdgeEvent────┤ (hop to main)
//                             EdgeSwipeRecognizer     ──GestureSlot──┤
//                                                                    ▼
//                       GestureSlot → Preferences.action(for:frontmostBundleID:) → ActionExecutor
//                       EdgeEvent   → EdgeActionPerformer
//
// AppDelegate calls start()/stop() for lifecycle (permission, sleep/wake, quit); the
// master switch decides whether a started engine is actually listening.

import AppKit
import Combine
import Foundation

final class GestureCoordinator: DeviceMonitorDelegate {

    static let shared = GestureCoordinator()

    private let deviceMonitor = DeviceMonitor()
    private let fingerRecognizer = FingerGestureRecognizer()
    private let edgeRecognizer = EdgeGestureRecognizer()
    private let edgeSwipeRecognizer = EdgeSwipeRecognizer()
    private let edgePerformer = EdgeActionPerformer()

    private let flags = Locked(FeatureFlags())
    private let frontmostBundleID = Locked<String?>(nil)
    /// Device of the frame currently being processed (multitouch thread only).
    private var currentDevice: TouchDevice?

    private var wantsRunning = false
    private var cancellables: Set<AnyCancellable> = []
    private var keyMonitor: Any?

    var isRunning: Bool { deviceMonitor.isRunning }

    private init() {
        deviceMonitor.delegate = self

        fingerRecognizer.onEvent = { [weak self] event in
            switch event {
            case .gesture(let slot):
                DispatchQueue.main.async { self?.perform(slot) }
            case .armClickSuppressor:
                ClickSuppressor.shared.arm()
            }
        }
        edgeRecognizer.onEvent = { [weak self] event in
            let device = self?.currentDevice
            DispatchQueue.main.async { self?.edgePerformer.handle(event, device: device) }
        }
        edgeSwipeRecognizer.isContact = { [fingerRecognizer] in fingerRecognizer.isFingerContact($0) }
        edgeSwipeRecognizer.onGesture = { [weak self] slot in
            DispatchQueue.main.async { self?.perform(slot) }
        }
        edgePerformer.performGesture = { [weak self] slot in self?.perform(slot) }

        let prefs = Preferences.shared
        Publishers.CombineLatest(prefs.$flags, prefs.$edge)
            .sink { [weak self] flags, edge in self?.apply(flags: flags, edge: edge) }
            .store(in: &cancellables)

        let workspace = NSWorkspace.shared
        frontmostBundleID.value = workspace.frontmostApplication?.bundleIdentifier
        workspace.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                self?.frontmostBundleID.value = app?.bundleIdentifier
            }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    func start() {
        wantsRunning = true
        refreshRunningState()
    }

    func stop() {
        wantsRunning = false
        refreshRunningState()
    }

    private func refreshRunningState() {
        let shouldRun = wantsRunning && flags.value.masterEnabled
        if shouldRun && !deviceMonitor.isRunning {
            deviceMonitor.start()
            installKeyMonitor()
            Log.info("Engine started.")
        } else if !shouldRun && deviceMonitor.isRunning {
            deviceMonitor.stop()
            removeKeyMonitor()
            edgePerformer.reset()
            TrackpadHaptics.shared.reset()
            Log.info("Engine stopped.")
        }
    }

    private func apply(flags newFlags: FeatureFlags, edge: EdgeSettings) {
        flags.value = newFlags
        fingerRecognizer.setConfig(FingerRecognizerConfig(
            threeFinger: newFlags.threeFinger,
            fourFinger: newFlags.fourFinger,
            forceClick: newFlags.cornerForceClick))
        edgeRecognizer.setConfig(EdgeRecognizerConfig(
            settings: edge,
            edgeControls: newFlags.edgeControls,
            topEdge: newFlags.topEdge))
        edgeSwipeRecognizer.setConfig(EdgeSwipeRecognizerConfig(
            twoFinger: newFlags.twoFingerEdgeSwipe,
            threeFinger: newFlags.threeFingerEdgeSwipe))
        if !newFlags.edgeControls { edgePerformer.reset() }
        refreshRunningState()
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

    // MARK: - Frames (multitouch thread)

    func didReceiveFingers(_ fingers: [MTFinger], timestamp: Double, device: TouchDevice) {
        let f = flags.value
        guard f.masterEnabled else { return }
        if f.threeFinger || f.fourFinger || f.cornerForceClick {
            fingerRecognizer.process(fingers: fingers, timestamp: timestamp)
        }
        // Edges are a trackpad thing — a Magic Mouse surface has none.
        if (f.edgeControls || f.topEdge) && !device.isMouse {
            currentDevice = device
            edgeRecognizer.process(fingers: fingers, timestamp: timestamp)
        }
        if (f.twoFingerEdgeSwipe || f.threeFingerEdgeSwipe) && !device.isMouse {
            edgeSwipeRecognizer.process(fingers: fingers, timestamp: timestamp)
        }
    }

    // MARK: - Mapped gestures (main thread)

    private func perform(_ slot: GestureSlot) {
        let f = flags.value
        guard f.masterEnabled, f.isEnabled(slot.family) else { return }
        let action = Preferences.shared.action(for: slot, frontmostBundleID: frontmostBundleID.value)
        guard action != .none else { return }
        Log.info("\(slot.rawValue) → \(action.displayName)")
        ActionExecutor.shared.execute(action)
    }
}
