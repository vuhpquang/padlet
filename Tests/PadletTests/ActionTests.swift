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
}
