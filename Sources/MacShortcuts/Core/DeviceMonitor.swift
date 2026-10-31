// Core/DeviceMonitor.swift
// Registers a touch-frame observer on every connected trackpad and starts event delivery.
//
// MTDeviceStart(device, 0) is required to begin receiving touch frames.
// The second argument is the run-loop mode (0 = default). We previously called it
// with only 1 argument — that was undefined behavior and corrupted the trackpad state.

import Foundation

// MARK: - Delegate Protocol

protocol DeviceMonitorDelegate: AnyObject {
    /// Called on the multitouch thread for every frame.
    /// `fingers` is empty on the frame(s) sent when the last finger lifts.
    /// `fromMouse` is true when the frame came from a Magic Mouse surface.
    func didReceiveFingers(_ fingers: [MTFinger], timestamp: Double, fromMouse: Bool)
}

// MARK: - Module-level state shared with the C callback

private weak var _activeMonitor: DeviceMonitor?

/// Devices identified as Magic Mouse. Written in start()/stop() before/after
/// delivery is running, read from the callback thread.
private var _mouseDevices: Set<MTDevice> = []

/// MultitouchSupport family IDs reported by Magic Mouse hardware.
private let magicMouseFamilyIDs: Set<Int32> = [112, 113]

// MARK: - DeviceMonitor

class DeviceMonitor {

    weak var delegate: DeviceMonitorDelegate?
    private var devices: [MTDevice] = []
    private(set) var isRunning = false

    func start() {
        let fw = MultitouchFramework.shared
        guard fw.isAvailable else {
            print("[MacShortcuts] DeviceMonitor: MultitouchSupport not available — gestures disabled.")
            return
        }
        guard !isRunning else { return }

        _activeMonitor = self

        guard let cfArray = fw.MTDeviceCreateList?() else {
            print("[MacShortcuts] DeviceMonitor: MTDeviceCreateList returned nil.")
            return
        }

        let count = CFArrayGetCount(cfArray)
        print("[MacShortcuts] DeviceMonitor: Found \(count) device(s).")
        guard count > 0 else { return }

        var mice: Set<MTDevice> = []
        for i in 0..<count {
            guard let rawPtr = CFArrayGetValueAtIndex(cfArray, i) else { continue }
            let device = UInt(bitPattern: rawPtr)
            devices.append(device)

            var family: Int32 = 0
            if let getFamily = fw.MTDeviceGetFamilyID, getFamily(device, &family) == 0,
               magicMouseFamilyIDs.contains(family) {
                mice.insert(device)
            }
            _mouseDevices = mice

            // Register our callback — this adds to the existing callback chain.
            fw.MTRegisterContactFrameCallback?(device, deviceTouchCallback)

            // Start event delivery to our callback.
            // runMode = 0 is the standard default. The previous bug was calling this
            // with only 1 arg (missing runMode), causing undefined behavior.
            fw.MTDeviceStart?(device, 0)

            print("[MacShortcuts] DeviceMonitor: Registered + started device \(i) (family \(family)\(mice.contains(device) ? ", mouse" : "")).")
        }

        isRunning = true
    }

    func stop() {
        let fw = MultitouchFramework.shared
        if fw.isAvailable {
            for device in devices {
                fw.MTDeviceStop?(device, 0)
            }
        }
        devices.removeAll()
        _activeMonitor = nil
        isRunning = false
        print("[MacShortcuts] DeviceMonitor: Stopped.")
    }
}

// MARK: - C Callback

private let deviceTouchCallback: MTContactFrameCallback = { device, fingerData, fingerCount, timestamp, _ in
    guard let monitor = _activeMonitor else { return }
    let fromMouse = _mouseDevices.contains(device)
    // Zero-count frames are forwarded too: they are how recognizers learn that
    // every finger has lifted.
    guard fingerCount > 0 else {
        monitor.delegate?.didReceiveFingers([], timestamp: timestamp, fromMouse: fromMouse)
        return
    }
    let fingersPtr = fingerData.assumingMemoryBound(to: MTFinger.self)
    let fingers = Array(UnsafeBufferPointer(start: fingersPtr, count: Int(fingerCount)))
    monitor.delegate?.didReceiveFingers(fingers, timestamp: timestamp, fromMouse: fromMouse)
}
