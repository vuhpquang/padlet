// Actions/ActionExecutor.swift
// Performs a GestureAction by synthesizing mouse / keyboard events (CGEvent) or
// launching an app. Needs Accessibility permission. Main thread.

import AppKit
import CoreGraphics
import Foundation

final class ActionExecutor {

    static let shared = ActionExecutor()

    private init() {}

    func execute(_ action: GestureAction) {
        switch action {
        case .none:
            break
        case .builtin(let builtin):
            perform(builtin)
        case .keystroke(let key, let modifiers):
            keystroke(key: key, modifiers: modifiers)
        case .openApp(let bundleID):
            openApp(bundleID: bundleID)
        case .runShortcut(let name):
            runShortcut(name)
        case .openURL(let url):
            openURL(url)
        case .pasteText(let text):
            paste(text)
        case .runCommand(let command):
            runCommand(command)
        }
    }

    private func perform(_ action: BuiltinAction) {
        switch action {
        case .middleClick:           middleClick()
        case .missionControl:        postKey(126, flags: .maskControl)                 // ⌃↑
        case .appExpose:             postKey(125, flags: .maskControl)                 // ⌃↓
        case .showDesktop:           postKey(103)                                      // F11
        case .spotlight:             postKey(49, flags: .maskCommand)                  // ⌘Space
        case .screenshot:            postKey(23, flags: [.maskCommand, .maskShift])    // ⇧⌘5
        case .lockScreen:            postKey(12, flags: [.maskCommand, .maskControl])  // ⌃⌘Q
        case .toggleDoNotDisturb:    DoNotDisturb.toggle()
        case .previousSpace:         postKey(123, flags: .maskControl)                 // ⌃←
        case .nextSpace:             postKey(124, flags: .maskControl)                 // ⌃→
        case .moveToNextDisplay:     WindowManager.moveToDisplay(offset: 1)
        case .moveToPreviousDisplay: WindowManager.moveToDisplay(offset: -1)
        case .maximizeWindow:        WindowManager.place(.fill)
        case .leftHalf:              WindowManager.place(.leftHalf)
        case .rightHalf:             WindowManager.place(.rightHalf)
        case .topHalf:               WindowManager.place(.topHalf)
        case .bottomHalf:            WindowManager.place(.bottomHalf)
        case .leftThird:             WindowManager.place(.leftThird)
        case .centerThird:           WindowManager.place(.centerThird)
        case .rightThird:            WindowManager.place(.rightThird)
        case .leftTwoThirds:         WindowManager.place(.leftTwoThirds)
        case .rightTwoThirds:        WindowManager.place(.rightTwoThirds)
        case .centerWindow:          WindowManager.place(.center)
        case .minimizeWindow:        WindowManager.minimize()
        case .toggleFullScreen:      WindowManager.toggleFullScreen()
        case .closeWindow:           WindowManager.close()
        case .previousTab:           postKey(48, flags: [.maskControl, .maskShift])    // ⌃⇧⇥
        case .nextTab:               postKey(48, flags: .maskControl)                  // ⌃⇥
        case .newTab:                postKey(17, flags: .maskCommand)                  // ⌘T
        case .closeTab:              postKey(13, flags: .maskCommand)                  // ⌘W
        case .reopenTab:             postKey(17, flags: [.maskCommand, .maskShift])    // ⇧⌘T
        case .back:                  postKey(33, flags: .maskCommand)                  // ⌘[
        case .forward:               postKey(30, flags: .maskCommand)                  // ⌘]
        case .previousApp:           FrontmostAppTracker.shared.activatePreviousApp()
        case .quitApp:               quitFrontmostApp()
        case .playPause:             MediaKeys.post(.play)
        case .nextTrack:             MediaKeys.post(.next)
        case .previousTrack:         MediaKeys.post(.previous)
        case .mute:                  MediaKeys.post(.mute)
        }
    }

    // MARK: - Primitives

    /// Posts a key-down/key-up pair for a virtual key code.
    func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    private func middleClick() {
        // CGEvent uses a top-left origin; NSEvent.mouseLocation is bottom-left.
        let location = NSEvent.mouseLocation
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let point = CGPoint(x: location.x, y: screenHeight - location.y)
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.otherMouseDown, .otherMouseUp] {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .center)?
                .post(tap: .cghidEventTap)
        }
    }

    private func keystroke(key: String, modifiers: NSEvent.ModifierFlags) {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.shift)   { flags.insert(.maskShift) }
        if modifiers.contains(.option)  { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        // Prefer the real key code: apps match shortcuts on it, and named keys need it.
        if let code = KeyCodes.code(for: key) {
            postKey(code, flags: flags)
            return
        }
        guard var scalar = key.utf16.first else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
            event?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &scalar)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    private func quitFrontmostApp() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.activationPolicy == .regular,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              app.bundleIdentifier != "com.apple.finder" else { return }
        app.terminate()
    }

    private func runShortcut(_ name: String) {
        guard !name.isEmpty else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        task.arguments = ["run", name]
        task.terminationHandler = { process in
            if process.terminationStatus != 0 {
                Log.error("ActionExecutor: shortcut \"\(name)\" exited with \(process.terminationStatus)")
            }
        }
        do { try task.run() } catch { Log.error("ActionExecutor: could not run shortcut \"\(name)\": \(error)") }
    }

    private func openURL(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // "example.com" → https://example.com; anything with a scheme opens as-is.
        let withScheme = trimmed.contains(":") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme) else {
            Log.error("ActionExecutor: not a URL: \(trimmed)")
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Puts the text on the clipboard, posts ⌘V, then puts the previous clipboard back.
    private func paste(_ text: String) {
        guard !text.isEmpty else { return }
        let board = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = (board.pasteboardItems ?? []).map { item in
            var copy: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { if let data = item.data(forType: type) { copy[type] = data } }
            return copy
        }
        board.clearContents()
        board.setString(text, forType: .string)
        let changeCount = board.changeCount
        postKey(9, flags: .maskCommand)                                      // ⌘V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            // Leave the clipboard alone if something else changed it meanwhile.
            guard board.changeCount == changeCount else { return }
            board.clearContents()
            let items = saved.map { entries -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in entries { item.setData(data, forType: type) }
                return item
            }
            if !items.isEmpty { board.writeObjects(items) }
        }
    }

    private func runCommand(_ command: String) {
        guard !command.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", command]
        task.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.terminationHandler = { process in
            if process.terminationStatus != 0 {
                Log.error("ActionExecutor: command exited with \(process.terminationStatus)")
            }
        }
        do { try task.run() } catch { Log.error("ActionExecutor: could not run command: \(error)") }
    }

    private func openApp(bundleID: String) {
        guard !bundleID.isEmpty else { return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            Log.error("ActionExecutor: no app for bundle ID \(bundleID)")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error = error { Log.error("ActionExecutor: could not open \(bundleID): \(error)") }
        }
    }
}
