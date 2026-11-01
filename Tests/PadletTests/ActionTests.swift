// Tests/PadletTests/ActionTests.swift
// GestureAction persistence (incl. settings written by older versions) and KeyCodes.

import AppKit
import XCTest
@testable import Padlet

final class ActionTests: XCTestCase {

    private func decode(_ json: String) throws -> GestureAction {
        try JSONDecoder().decode(GestureAction.self, from: Data(json.utf8))
    }

    private func roundTrip(_ action: GestureAction) throws -> GestureAction {
        try JSONDecoder().decode(GestureAction.self, from: JSONEncoder().encode(action))
    }

    func testDecodesActionsSavedByOlderVersions() throws {
        XCTAssertEqual(try decode(#"{"type":"middleClick"}"#), .middleClick)
        XCTAssertEqual(try decode(#"{"type":"missionControl"}"#), .missionControl)
        XCTAssertEqual(try decode(#"{"type":"showDesktop"}"#), .showDesktop)
        XCTAssertEqual(try decode(#"{"type":"nextTab"}"#), .nextTab)
        XCTAssertEqual(try decode(#"{"type":"none"}"#), GestureAction.none)
        XCTAssertEqual(try decode(#"{"type":"keystroke","key":"w","modifiers":1048576}"#),
                       .keystroke(key: "w", modifiers: .command))
        XCTAssertEqual(try decode(#"{"type":"openApp","bundleID":"com.apple.Safari"}"#),
                       .openApp(bundleID: "com.apple.Safari"))
    }

    func testUnknownTypeFallsBackToNone() throws {
        XCTAssertEqual(try decode(#"{"type":"somethingFromTheFuture"}"#), GestureAction.none)
    }

    func testEveryActionRoundTrips() throws {
        var all: [GestureAction] = [.none, .runShortcut(name: "Focus Mode"),
                                    .openURL(url: "https://github.com"), .pasteText(text: "Hi,\nthanks!"),
                                    .runCommand(command: "open -a Notes"),
                                    .keystroke(key: "←", modifiers: [.control, .option]),
                                    .openApp(bundleID: "com.apple.Notes")]
        all += BuiltinAction.allCases.map(GestureAction.builtin)
        for action in all {
            XCTAssertEqual(try roundTrip(action), action, "\(action)")
        }
    }

    func testBuiltinRawValuesAreStable() {
        // Persisted names — renaming one silently resets users' gestures to None.
        XCTAssertEqual(BuiltinAction.middleClick.rawValue, "middleClick")
        XCTAssertEqual(BuiltinAction.moveToNextDisplay.rawValue, "moveToNextDisplay")
        XCTAssertEqual(BuiltinAction.previousSpace.rawValue, "previousSpace")
    }

    func testEveryBuiltinHasAGroupAndTitle() {
        let grouped = BuiltinAction.Group.allCases.flatMap(BuiltinAction.cases(in:))
        XCTAssertEqual(grouped.count, BuiltinAction.allCases.count)
        XCTAssertEqual(Set(BuiltinAction.allCases.map(\.title)).count, BuiltinAction.allCases.count)
    }

    func testPickerKeepsCustomValuesWhenRePicked() {
        let shortcut = GestureAction.keystroke(key: "t", modifiers: [.command, .shift])
        XCTAssertEqual(shortcut.pickerValue, .keystroke(key: "", modifiers: []))
        XCTAssertEqual(shortcut.replacing(withPicked: .keystroke(key: "", modifiers: [])), shortcut)
        XCTAssertEqual(shortcut.replacing(withPicked: .nextTab), .nextTab)
        let run = GestureAction.runShortcut(name: "Dim")
        XCTAssertEqual(run.replacing(withPicked: .runShortcut(name: "")), run)
    }

    func testSummaries() {
        XCTAssertEqual(GestureAction.keystroke(key: "t", modifiers: [.command, .shift]).summary, "⇧⌘T")
        XCTAssertEqual(GestureAction.runShortcut(name: "Dim").summary, "“Dim”")
        XCTAssertEqual(GestureAction.builtin(.leftHalf).summary, "Left Half")
    }

    func testKeyCodesNamedKeys() {
        XCTAssertEqual(KeyCodes.code(for: "←"), 123)
        XCTAssertEqual(KeyCodes.code(for: "F5"), 96)
        XCTAssertEqual(KeyCodes.code(for: "Space"), 49)
        XCTAssertEqual(KeyCodes.name(for: 126), "↑")
        XCTAssertEqual(KeyCodes.name(for: 53), "⎋")
    }

    func testKeyCodesCharactersRoundTrip() {
        // Whatever the layout, a character key maps back to the code that types it.
        for code: CGKeyCode in [0, 1, 13, 17, 31] {
            guard let name = KeyCodes.name(for: code) else { continue }
            XCTAssertEqual(KeyCodes.code(for: name), code, "key \(code) → \(name)")
        }
    }

    func testKeyCodesDisplayOrder() {
        XCTAssertEqual(KeyCodes.display(key: "k", modifiers: [.command, .shift, .control, .option]), "⌃⌥⇧⌘K")
        XCTAssertEqual(KeyCodes.display(key: "F5", modifiers: []), "F5")
    }

    func testCustomActionsKeepValuesWhenRePicked() {
        for action: GestureAction in [.openURL(url: "x.com"), .pasteText(text: "a"), .runCommand(command: "ls")] {
            XCTAssertEqual(action.replacing(withPicked: action.pickerValue), action)
            XCTAssertNotEqual(action.pickerValue, action)
        }
    }

    // MARK: Window placements (pure geometry, AX coordinates)

    private let area = CGRect(x: 0, y: 25, width: 1500, height: 900)

    func testHalvesAndThirdsTileTheScreen() {
        let r = { WindowManager.rect(for: $0, in: self.area, current: CGSize(width: 800, height: 600)) }
        XCTAssertEqual(r(.leftHalf), CGRect(x: 0, y: 25, width: 750, height: 900))
        XCTAssertEqual(r(.rightHalf), CGRect(x: 750, y: 25, width: 750, height: 900))
        XCTAssertEqual(r(.topHalf), CGRect(x: 0, y: 25, width: 1500, height: 450))
        XCTAssertEqual(r(.bottomHalf), CGRect(x: 0, y: 475, width: 1500, height: 450))
        XCTAssertEqual(r(.leftThird).width + r(.centerThird).width + r(.rightThird).width, area.width)
        XCTAssertEqual(r(.leftThird).maxX, r(.centerThird).minX)
        XCTAssertEqual(r(.centerThird).maxX, r(.rightThird).minX)
        XCTAssertEqual(r(.leftTwoThirds).maxX, r(.rightThird).minX)
        XCTAssertEqual(r(.rightTwoThirds).minX, r(.leftThird).maxX)
        XCTAssertEqual(r(.fill), area)
    }

    func testCenterKeepsSizeAndClampsToScreen() {
        let centered = WindowManager.rect(for: .center, in: area, current: CGSize(width: 800, height: 600))
        XCTAssertEqual(centered, CGRect(x: 350, y: 175, width: 800, height: 600))
        let huge = WindowManager.rect(for: .center, in: area, current: CGSize(width: 4000, height: 3000))
        XCTAssertEqual(huge, area)
    }

    func testToggleHotKeyDefaultsToNoneAndPersists() throws {
        let old = try JSONDecoder().decode(GeneralSettings.self, from: Data(#"{"appearance":"dark"}"#.utf8))
        XCTAssertNil(old.toggleHotKey)
        var settings = GeneralSettings()
        settings.toggleHotKey = KeyCombo(key: "p", modifiers: NSEvent.ModifierFlags([.command, .option]).rawValue)
        let back = try JSONDecoder().decode(GeneralSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(back.toggleHotKey, settings.toggleHotKey)
        XCTAssertEqual(back.toggleHotKey?.display, "⌥⌘P")
    }
}
