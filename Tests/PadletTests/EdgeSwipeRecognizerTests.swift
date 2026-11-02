import XCTest
@testable import Padlet

final class EdgeSwipeRecognizerTests: XCTestCase {

    private var recognizer: EdgeSwipeRecognizer!
    private var slots: [GestureSlot] = []

    override func setUp() {
        recognizer = EdgeSwipeRecognizer()
        recognizer.setConfig(EdgeSwipeRecognizerConfig(twoFinger: true, threeFinger: true))
        slots = []
        recognizer.onGesture = { [unowned self] in self.slots.append($0) }
    }

    /// `n` fingers spread across the edge's direction, centred on (x, y).
    private func fingers(_ n: Int, x: Float, y: Float, spreadAlongY: Bool) -> [MTFinger] {
        (0..<n).map { i in
            let offset = (Float(i) - Float(n - 1) / 2) * 0.08
            return MTFinger.make(id: Int32(i + 1),
                                 x: spreadAlongY ? x : x + offset,
                                 y: spreadAlongY ? y + offset : y)
        }
    }

    /// Feeds a straight swipe from `from` to `to` in `steps` frames over `duration`, then lifts.
    private func swipe(_ n: Int, from: (Float, Float), to: (Float, Float),
                       spreadAlongY: Bool, duration: Double = 0.2, steps: Int = 5) {
        for i in 0...steps {
            let t = Float(i) / Float(steps)
            let x = from.0 + (to.0 - from.0) * t
            let y = from.1 + (to.1 - from.1) * t
            recognizer.process(fingers: fingers(n, x: x, y: y, spreadAlongY: spreadAlongY),
                               timestamp: duration * Double(t))
        }
        recognizer.process(fingers: [], timestamp: duration + 0.05)
    }

    func testTwoFingerSwipeInFromLeft() {
        swipe(2, from: (0.05, 0.5), to: (0.35, 0.5), spreadAlongY: true)
        XCTAssertEqual(slots, [.twoFingerFromLeft])
    }

    func testTwoFingerSwipeInFromRight() {
        swipe(2, from: (0.95, 0.5), to: (0.65, 0.5), spreadAlongY: true)
        XCTAssertEqual(slots, [.twoFingerFromRight])
    }

    func testThreeFingerSwipeInFromTop() {
        swipe(3, from: (0.5, 0.95), to: (0.5, 0.6), spreadAlongY: false)
        XCTAssertEqual(slots, [.threeFingerFromTop])
    }

    func testThreeFingerSwipeInFromBottom() {
        swipe(3, from: (0.5, 0.05), to: (0.5, 0.4), spreadAlongY: false)
        XCTAssertEqual(slots, [.threeFingerFromBottom])
    }

    func testFiresOncePerTouch() {
        swipe(2, from: (0.05, 0.5), to: (0.8, 0.5), spreadAlongY: true, steps: 12)
        XCTAssertEqual(slots, [.twoFingerFromLeft])
    }

    func testSwipeStartingMidPadIsIgnored() {
        swipe(2, from: (0.4, 0.5), to: (0.8, 0.5), spreadAlongY: true)
        XCTAssertEqual(slots, [])
    }

    func testSwipeAlongTheEdgeIsIgnored() {
        swipe(2, from: (0.05, 0.2), to: (0.08, 0.8), spreadAlongY: true)
        XCTAssertEqual(slots, [])
    }

    func testSlowDragIsIgnored() {
        swipe(2, from: (0.05, 0.5), to: (0.35, 0.5), spreadAlongY: true, duration: 2.0)
        XCTAssertEqual(slots, [])
    }

    func testThirdFingerLandingLateUpgradesToThreeFingerSwipe() {
        recognizer.process(fingers: fingers(2, x: 0.05, y: 0.5, spreadAlongY: true), timestamp: 0)
        recognizer.process(fingers: fingers(3, x: 0.05, y: 0.5, spreadAlongY: true), timestamp: 0.04)
        recognizer.process(fingers: fingers(3, x: 0.3, y: 0.5, spreadAlongY: true), timestamp: 0.2)
        XCTAssertEqual(slots, [.threeFingerFromLeft])
    }

    func testSecondFingerAfterALongSingleTouchIsIgnored() {
        recognizer.process(fingers: fingers(1, x: 0.05, y: 0.5, spreadAlongY: true), timestamp: 0)
        recognizer.process(fingers: fingers(2, x: 0.05, y: 0.5, spreadAlongY: true), timestamp: 0.6)
        recognizer.process(fingers: fingers(2, x: 0.35, y: 0.5, spreadAlongY: true), timestamp: 0.8)
        XCTAssertEqual(slots, [])
    }

    func testFourFingersAreIgnored() {
        swipe(4, from: (0.05, 0.5), to: (0.35, 0.5), spreadAlongY: true)
        XCTAssertEqual(slots, [])
    }

    func testDisabledFamilyEmitsNothingButOtherStillWorks() {
        recognizer.setConfig(EdgeSwipeRecognizerConfig(twoFinger: false, threeFinger: true))
        swipe(2, from: (0.05, 0.5), to: (0.35, 0.5), spreadAlongY: true)
        swipe(3, from: (0.05, 0.5), to: (0.35, 0.5), spreadAlongY: true)
        XCTAssertEqual(slots, [.threeFingerFromLeft])
    }

    func testEdgeSwipeSlotsBelongToTheirFamilies() {
        for edge in TrackpadEdge.allCases {
            XCTAssertEqual(GestureSlot.edgeSwipe(fingers: 2, from: edge)?.family, .twoFingerEdgeSwipe)
            XCTAssertEqual(GestureSlot.edgeSwipe(fingers: 3, from: edge)?.family, .threeFingerEdgeSwipe)
        }
        XCTAssertNil(GestureSlot.edgeSwipe(fingers: 4, from: .left))
        XCTAssertFalse(FeatureFlags().twoFingerEdgeSwipe)
        XCTAssertFalse(FeatureFlags().threeFingerEdgeSwipe)
    }
}
