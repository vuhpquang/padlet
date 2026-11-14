import XCTest
import AppShellCore
@testable import Padlet

final class SettingsTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let name = "padlet.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testLegacySixSlotMappingStillLoads() throws {
        let legacy = """
        {"threeFingerTap":{"type":"none"},"threeFingerClick":{"type":"keystroke","key":"w","modifiers":1048576},
         "cornerTopLeft":{"type":"showDesktop"},"cornerTopRight":{"type":"none"},
         "cornerBottomLeft":{"type":"openApp","bundleID":"com.apple.Safari"},"cornerBottomRight":{"type":"none"}}
        """
        let mapping = try JSONDecoder().decode(GestureMapping.self, from: Data(legacy.utf8))
        XCTAssertEqual(mapping[.threeFingerTap], GestureAction.none)
        XCTAssertEqual(mapping[.threeFingerClick], .keystroke(key: "w", modifiers: .command))
        XCTAssertEqual(mapping[.cornerTopLeft], .showDesktop)
        XCTAssertEqual(mapping[.cornerBottomLeft], .openApp(bundleID: "com.apple.Safari"))
        // Slots that didn't exist in v1 get their defaults.
        XCTAssertEqual(mapping[.topEdgeSwipeLeft], .previousSpace)
        XCTAssertEqual(mapping[.fourFingerTap], GestureAction.none)
    }

    func testMappingRoundTrip() throws {
        var mapping = GestureMapping.defaults
        mapping[.fourFingerClick] = .nextTab
        mapping[.cornerTopRight] = .keystroke(key: "k", modifiers: [.command, .shift])
        let decoded = try JSONDecoder().decode(GestureMapping.self, from: JSONEncoder().encode(mapping))
        XCTAssertEqual(decoded, mapping)
    }

    func testUnknownActionTypeDecodesAsNone() throws {
        let action = try JSONDecoder().decode(GestureAction.self, from: Data(#"{"type":"teleport"}"#.utf8))
        XCTAssertEqual(action, GestureAction.none)
    }

    func testLegacySwapSidesBecomesPerEdgeFunctions() throws {
        let edge = try JSONDecoder().decode(EdgeSettings.self, from: Data(#"{"swapSides":true,"edgeWidth":0.1}"#.utf8))
        XCTAssertEqual(edge.leftFunction, .volume)
        XCTAssertEqual(edge.rightFunction, .brightness)
        XCTAssertEqual(edge.edgeWidth, 0.1)
        XCTAssertEqual(edge.sensitivity, EdgeSettings().sensitivity)
    }

    func testPartialFeatureFlagsKeepDefaults() throws {
        let flags = try JSONDecoder().decode(FeatureFlags.self, from: Data(#"{"threeFinger":false}"#.utf8))
        XCTAssertFalse(flags.threeFinger)
        XCTAssertTrue(flags.fourFinger)
        XCTAssertTrue(flags.masterEnabled)
    }

    func testAppProfileOverridesGlobalMapping() {
        let prefs = Preferences(defaults: freshDefaults())
        var profile = AppProfile(bundleID: "com.google.Chrome", name: "Chrome")
        profile[.threeFingerTap] = .nextTab
        prefs.profiles = [profile]

        XCTAssertEqual(prefs.action(for: .threeFingerTap, frontmostBundleID: "com.google.Chrome"), .nextTab)
        XCTAssertEqual(prefs.action(for: .threeFingerTap, frontmostBundleID: "com.apple.Safari"), .middleClick)
        // Slots without an override fall through to the global mapping.
        XCTAssertEqual(prefs.action(for: .cornerTopLeft, frontmostBundleID: "com.google.Chrome"), .missionControl)

        prefs.profiles[0].enabled = false
        XCTAssertEqual(prefs.action(for: .threeFingerTap, frontmostBundleID: "com.google.Chrome"), .middleClick)

        prefs.profiles[0].enabled = true
        prefs.flags.appProfiles = false
        XCTAssertEqual(prefs.action(for: .threeFingerTap, frontmostBundleID: "com.google.Chrome"), .middleClick)
    }

    func testPreferencesPersist() {
        let defaults = freshDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.flags.fourFinger = false
        prefs.edge.leftFunction = .zoom
        prefs.mapping[.fourFingerTap] = .appExpose
        prefs.profiles = [AppProfile(bundleID: "a.b", name: "AB")]

        let reloaded = Preferences(defaults: defaults)
        XCTAssertFalse(reloaded.flags.fourFinger)
        XCTAssertEqual(reloaded.edge.leftFunction, .zoom)
        XCTAssertEqual(reloaded.mapping[.fourFingerTap], .appExpose)
        XCTAssertEqual(reloaded.profiles.map(\.bundleID), ["a.b"])
    }

    @MainActor func testUpdateSettingsAdapterUsesExistingKeys() {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "padlet-test-\(UUID())")!)
        let store = PadletUpdateSettings(prefs: prefs)
        store.autoCheck = false
        store.autoInstall = true
        XCTAssertFalse(prefs.general.autoCheckUpdates)
        XCTAssertTrue(prefs.general.autoInstallUpdates)
        XCTAssertEqual(AppIdentity.padlet.repo, "vuhpquang/padlet")
    }

    func testHapticStrengthOrdering() {
        let ids = HapticStrength.allCases.filter { $0 != .off }.map(TrackpadHaptics.actuationID(for:))
        XCTAssertEqual(ids, ids.sorted())
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testTopAppSwitcherDefaultsOnAndRoundTrips() throws {
        let old = try JSONDecoder().decode(EdgeSettings.self, from: Data(#"{"edgeWidth":0.1}"#.utf8))
        XCTAssertTrue(old.topAppSwitcher)
        var edge = EdgeSettings()
        edge.topAppSwitcher = false
        let back = try JSONDecoder().decode(EdgeSettings.self, from: JSONEncoder().encode(edge))
        XCTAssertFalse(back.topAppSwitcher)
    }

    func testSwitcherBackgroundDefaultsToGlassAndRoundTrips() throws {
        let old = try JSONDecoder().decode(EdgeSettings.self, from: Data(#"{"topAppSwitcher":true}"#.utf8))
        XCTAssertEqual(old.switcherBackground, .liquidGlass)
        var edge = EdgeSettings()
        edge.switcherBackground = .blur
        let data = try JSONEncoder().encode(edge)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""switcherBackground":"blur""#))
        XCTAssertEqual(try JSONDecoder().decode(EdgeSettings.self, from: data).switcherBackground, .blur)
    }
}
