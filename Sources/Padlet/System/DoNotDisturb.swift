// System/DoNotDisturb.swift
// macOS has no public API to switch Focus, so Padlet runs a shortcut the user creates once in
// the Shortcuts app ("Set Focus → Do Not Disturb → Toggle"). If it's missing, explain how.

import AppKit

enum DoNotDisturb {

    static let shortcutName = "Toggle Do Not Disturb"

    static func toggle() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        task.arguments = ["run", shortcutName]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.terminationHandler = { process in
            guard process.terminationStatus != 0 else { return }
            Log.error("DoNotDisturb: shortcut \"\(shortcutName)\" failed (\(process.terminationStatus))")
            DispatchQueue.main.async(execute: showSetupHelp)
        }
        do { try task.run() } catch { DispatchQueue.main.async(execute: showSetupHelp) }
    }

    /// One-time setup instructions, with the name copied to the clipboard.
    static func showSetupHelp() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(shortcutName, forType: .string)
        let alert = NSAlert()
        alert.messageText = "Set up Do Not Disturb"
        alert.informativeText = """
        macOS lets apps switch Focus only through Shortcuts. Create it once:

        1. In Shortcuts, click + to make a new shortcut.
        2. Add the “Set Focus” action, choose Do Not Disturb, and set it to Toggle.
        3. Name the shortcut “\(shortcutName)” (already copied — just paste).
        """
        alert.addButton(withTitle: "Open Shortcuts")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
        }
    }
}
