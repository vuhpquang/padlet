import XCTest
@testable import Padlet

final class FingerGestureRecognizerTests: XCTestCase {

    private var recognizer: FingerGestureRecognizer!
    private var events: [FingerEvent] = []

    override func setUp() {
        recognizer = FingerGestureRecognizer()
        events = []
        recognizer.onEvent = { [unowned self] in self.events.append($0) }
    }

    private func fingers(_ n: Int, vx: Float = 0) -> [MTFinger] {
        (0..<n).map { MTFinger.make(id: Int32($0 + 1), x: 0.35 + Float($0) * 0.1, y: 0.5, vx: vx) }
    }

    private var gestures: [GestureSlot] {
        events.compactMap { if case .gesture(let s) = $0 { return s } else { return nil } }
    }

    func testThreeFingerTap() {
        recognizer.process(fingers: fingers(3), timestamp: 0)
        recognizer.process(fingers: fingers(3), timestamp: 0.1)
        recognizer.process(fingers: [], timestamp: 0.15)
        XCTAssertEqual(gestures, [.threeFingerTap])
    }

    func testFourFingerTapWhenFingersLandOneByOne() {
        recognizer.process(fingers: fingers(3), timestamp: 0)
        recognizer.process(fingers: fingers(4), timestamp: 0.03)
        recognizer.process(fingers: [], timestamp: 0.12)
        XCTAssertEqual(gestures, [.fourFingerTap])
    }

    func testHoldIsAClickAndNotAlsoATap() {
        recognizer.process(fingers: fingers(3), timestamp: 0)
        recognizer.process(fingers: fingers(3), timestamp: 0.2)
        recognizer.process(fingers: [], timestamp: 0.3)
        XCTAssertEqual(gestures, [.threeFingerClick])
    }

    func testFourFingerHold() {
        recognizer.process(fingers: fingers(4), timestamp: 0)
        recognizer.process(fingers: fingers(4), timestamp: 0.2)
        XCTAssertEqual(gestures, [.fourFingerClick])
    }

    func testMovingFingersAreAScrollNotATap() {
        recognizer.process(fingers: fingers(3, vx: 0.5), timestamp: 0)
        recognizer.process(fingers: fingers(3, vx: 0.5), timestamp: 0.1)
        recognizer.process(fingers: [], timestamp: 0.15)
        XCTAssertEqual(gestures, [])
    }

    func testDisabledFamilyEmitsNothingButOthersStillWork() {
        recognizer.setConfig(FingerRecognizerConfig(threeFinger: false, fourFinger: true, forceClick: true))
        recognizer.process(fingers: fingers(3), timestamp: 0)
        recognizer.process(fingers: [], timestamp: 0.1)
        XCTAssertEqual(gestures, [])

        recognizer.process(fingers: fingers(4), timestamp: 1)
        recognizer.process(fingers: [], timestamp: 1.1)
        XCTAssertEqual(gestures, [.fourFingerTap])
    }

    func testCooldownPreventsDoubleFire() {
        recognizer.process(fingers: fingers(3), timestamp: 0)
        recognizer.process(fingers: [], timestamp: 0.1)
        recognizer.process(fingers: fingers(3), timestamp: 0.2)   // re-registration during lift
        recognizer.process(fingers: [], timestamp: 0.3)
        XCTAssertEqual(gestures, [.threeFingerTap])
    }

    func testCornerForceClickFiresOncePerPress() {
        let press = [MTFinger.make(id: 1, x: 0.15, y: 0.85, pressure: 0.9)]
        recognizer.process(fingers: press, timestamp: 0)
        recognizer.process(fingers: press, timestamp: 0.01)
        XCTAssertEqual(gestures, [.cornerTopLeft])
        XCTAssertTrue(events.contains(.armClickSuppressor))
    }

    func testNormalPressureInCornerDoesNothing() {
        recognizer.process(fingers: [MTFinger.make(id: 1, x: 0.85, y: 0.15, pressure: 0.75)], timestamp: 0)
        XCTAssertEqual(events, [])
    }

    func testForceClickDisabledDoesNotArmSuppressor() {
        recognizer.setConfig(FingerRecognizerConfig(threeFinger: true, fourFinger: true, forceClick: false))
        recognizer.process(fingers: [MTFinger.make(id: 1, x: 0.15, y: 0.85, pressure: 0.95)], timestamp: 0)
        XCTAssertEqual(events, [])
    }

    func testPalmIsIgnored() {
        let palm = MTFinger.make(id: 9, x: 0.5, y: 0.1, size: 1.2)
        recognizer.process(fingers: fingers(2) + [palm], timestamp: 0)
        recognizer.process(fingers: [], timestamp: 0.1)
        XCTAssertEqual(gestures, [])
    }
}
