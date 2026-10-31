// App/main.swift — entry point (SwiftPM executables can't use @main with an NSApplicationDelegate here).

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon (LSUIElement too)
app.run()
