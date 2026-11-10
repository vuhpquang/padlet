// Tests/PadletTests/AppSwitcherScreenTests.swift
// Which display the top-edge app switcher appears on.

import AppKit
import XCTest
@testable import Padlet

final class AppSwitcherScreenTests: XCTestCase {

    // Built-in at the origin, one external above it, one to its right.
    private let builtIn = NSRect(x: 0, y: 0, width: 1728, height: 1117)
    private let above = NSRect(x: 0, y: 1117, width: 2560, height: 1440)
    private let right = NSRect(x: 1728, y: 0, width: 1920, height: 1080)

    func testNoDisplays() {
        XCTAssertNil(AppSwitcher.targetIndex(mouse: .zero, frames: []))
    }

    func testSingleDisplayAlwaysWins() {
        XCTAssertEqual(AppSwitcher.targetIndex(mouse: NSPoint(x: 500, y: 1117), frames: [builtIn]), 0)
        XCTAssertEqual(AppSwitcher.targetIndex(mouse: NSPoint(x: -50, y: 5000), frames: [builtIn]), 0)
    }

    func testPicksDisplayUnderPointer() {
        let frames = [builtIn, above, right]
        XCTAssertEqual(AppSwitcher.targetIndex(mouse: NSPoint(x: 800, y: 500), frames: frames), 0)
        XCTAssertEqual(AppSwitcher.targetIndex(mouse: NSPoint(x: 800, y: 2556), frames: frames), 1)
        XCTAssertEqual(AppSwitcher.targetIndex(mouse: NSPoint(x: 3000, y: 1079), frames: frames), 2)
    }

    func testPointerOffEveryDisplayPicksNearest() {
        let frames = [builtIn, right]
        // Above the right-hand display, in the gap left by its shorter height.
        XCTAssertEqual(AppSwitcher.targetIndex(mouse: NSPoint(x: 3000, y: 1100), frames: frames), 1)
        XCTAssertEqual(AppSwitcher.targetIndex(mouse: NSPoint(x: -10, y: 300), frames: frames), 0)
    }
}
