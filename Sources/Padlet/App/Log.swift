// App/Log.swift
// Unified logging (Console.app → subsystem "com.vuhpquang.padlet"); DEBUG builds also print.

import Foundation
import os

enum Log {
    private static let logger = Logger(subsystem: "com.vuhpquang.padlet", category: "padlet")

    static func info(_ message: @autoclosure () -> String) {
        let text = message()
        logger.info("\(text, privacy: .public)")
        #if DEBUG
        print("[Padlet] \(text)")
        #endif
    }

    static func error(_ message: @autoclosure () -> String) {
        let text = message()
        logger.error("\(text, privacy: .public)")
        #if DEBUG
        print("[Padlet] ERROR \(text)")
        #endif
    }
}
