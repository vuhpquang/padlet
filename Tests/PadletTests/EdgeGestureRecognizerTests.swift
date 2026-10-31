import CoreGraphics
import XCTest
@testable import Padlet

final class EdgeGestureRecognizerTests: XCTestCase {

    private var clock: TimeInterval = 100
    private var flags: CGEventFlags = []
    private var recognizer: EdgeGestureRecognizer!
    private var events: [EdgeEvent] = []
    private let anchor = CGPoint(x: 100, y: 200)

    override func setUp() {
        clock = 100
        flags = []
        events = []
        recognizer = EdgeGestureRecognizer(now: { [unowned self] in self.clock },
                                           modifiers: { [unowned self] in self.flags },
                                           pointer: { [unowned self] in self.anchor })
        recognizer.onEvent = { [unowned self] in self.events.append($0) }
    }

    private func configure(_ edit: (inout EdgeRecognizerConfig) -> Void) {
        var c = EdgeRecognizerConfig()
        edit(&c)
        recognizer.setConfig(c)
    }

    /// Feeds one finger along `points` (x, y, t), then lifts it.
    private func drag(_ points: [(Float, Float, Double)], id: Int32 = 1, lift: Bool = true) {
        for (x, y, t) in points {
            recognizer.process(fingers: [MTFinger.make(id: id, x: x, y: y)], timestamp: t)
        }
        if lift { recognizer.process(fingers: [], timestamp: (points.last?.2 ?? 0) + 0.01) }
    }

    // MARK: Slides

    func testRightEdgeSlideControlsVolume() {
        drag([(0.97, 0.5, 0), (0.97, 0.52, 0.01), (0.97, 0.6, 0.02)])
        XCTAssertEqual(events.first, .slideBegan(.volume, anchor: anchor))
        guard case .slid(.volume, let delta, false) = events[1] else { return XCTFail("\(events)") }
        XCTAssertEqual(delta, 0.08 * 1.5, accuracy: 0.0001)
        XCTAssertEqual(events.last, .slideEnded)
    }

    func testLeftEdgeUsesConfiguredFunction() {
        configure { $0.settings.leftFunction = .scroll }
        drag([(0.02, 0.5, 0), (0.02, 0.45, 0.01)])
        XCTAssertEqual(events.first, .slideBegan(.scroll, anchor: anchor))
    }

    func testEdgeSetToOffDoesNothing() {
        configure { $0.settings.rightFunction = .off }
        drag([(0.97, 0.5, 0), (0.97, 0.6, 0.01), (0.97, 0.7, 0.02)])
        XCTAssertEqual(events, [])
    }

    func testFreezeCursorOffSendsNoAnchor() {
        configure { $0.settings.freezeCursor = false }
        drag([(0.97, 0.5, 0), (0.97, 0.55, 0.01)])
        XCTAssertEqual(events.first, .slideBegan(.volume, anchor: nil))
    }

    func testSidewaysMoveFromEdgeIsAPointerMove() {
        drag([(0.97, 0.5, 0), (0.9, 0.505, 0.01), (0.7, 0.51, 0.02), (0.7, 0.7, 0.03)])
        XCTAssertEqual(events, [])
    }

    func testSecondFingerCancelsSlide() {
        drag([(0.97, 0.5, 0), (0.97, 0.55, 0.01)], lift: false)
        recognizer.process(fingers: [MTFinger.make(id: 1, x: 0.97, y: 0.6), MTFinger.make(id: 2, x: 0.5, y: 0.5)],
                           timestamp: 0.02)
        recognizer.process(fingers: [MTFinger.make(id: 1, x: 0.97, y: 0.8)], timestamp: 0.03)
        XCTAssertEqual(events.filter { if case .slid = $0 { return true } else { return false } }.count, 0)
        XCTAssertEqual(events.last, .slideEnded)
    }

    func testFineControlWithShiftOption() {
        drag([(0.97, 0.5, 0), (0.97, 0.52, 0.01)], lift: false)
        flags = [.maskShift, .maskAlternate]
        recognizer.process(fingers: [MTFinger.make(id: 1, x: 0.97, y: 0.6)], timestamp: 0.02)
        guard case .slid(_, let delta, true) = events.last else { return XCTFail("\(events)") }
        XCTAssertEqual(delta, 0.08 * 1.5 / 4, accuracy: 0.0001)
    }

    func testRequireModifier() {
        configure { $0.settings.requireModifier = true }
        drag([(0.97, 0.5, 0), (0.97, 0.6, 0.01)])
        XCTAssertEqual(events, [])

        flags = .maskAlternate
        drag([(0.97, 0.5, 1), (0.97, 0.6, 1.01)], id: 2)
        XCTAssertEqual(events.first, .slideBegan(.volume, anchor: anchor))
    }

    func testBottomQuarterOnly() {
        configure { $0.settings.bottomQuarterOnly = true }
        drag([(0.97, 0.5, 0), (0.97, 0.6, 0.01)])
        XCTAssertEqual(events, [])
        drag([(0.97, 0.15, 1), (0.97, 0.2, 1.01)], id: 2)
        XCTAssertEqual(events.first, .slideBegan(.volume, anchor: anchor))
    }

    func testTypingGuard() {
        recognizer.noteKeyPress()          // at t=100
        clock = 100.1
        drag([(0.97, 0.5, 0), (0.97, 0.6, 0.01)])
        XCTAssertEqual(events, [])
        clock = 101
        drag([(0.97, 0.5, 1), (0.97, 0.6, 1.01)], id: 2)
        XCTAssertFalse(events.isEmpty)
    }

    // MARK: Taps and swipes

    func testDoubleTapTopRightCornerMutes() {
        drag([(0.95, 0.95, 0), (0.95, 0.95, 0.05)])
        drag([(0.95, 0.95, 0.2), (0.95, 0.95, 0.25)], id: 2)
        XCTAssertEqual(events, [.armClickSuppressor, .doubleTap(.muteCorner)])
    }

    func testSingleTapDoesNothing() {
        drag([(0.95, 0.95, 0), (0.95, 0.95, 0.05)])
        XCTAssertEqual(events, [])
    }

    func testMediaStripSwipe() {
        drag([(0.5, 0.03, 0), (0.6, 0.03, 0.05), (0.7, 0.035, 0.1)])
        XCTAssertEqual(events, [.mediaSwipe(forward: true, restore: anchor)])
    }

    func testMediaStripSwipeInverted() {
        configure { $0.settings.invertMediaSwipe = true }
        drag([(0.5, 0.03, 0), (0.7, 0.03, 0.1)])
        XCTAssertEqual(events, [.mediaSwipe(forward: false, restore: anchor)])
    }

    func testMediaTapOnlyWhenEnabled() {
        drag([(0.5, 0.03, 0), (0.5, 0.03, 0.05)])
        drag([(0.5, 0.03, 0.2), (0.5, 0.03, 0.25)], id: 2)
        XCTAssertEqual(events, [])

        configure { $0.settings.mediaTap = true }
        drag([(0.5, 0.03, 1), (0.5, 0.03, 1.05)], id: 3)
        drag([(0.5, 0.03, 1.2), (0.5, 0.03, 1.25)], id: 4)
        XCTAssertEqual(events, [.armClickSuppressor, .doubleTap(.mediaStrip)])
    }

    func testQuickTopSwipe() {
        drag([(0.5, 0.97, 0), (0.3, 0.97, 0.1)])
        XCTAssertEqual(events, [.topSwipe(.topEdgeSwipeLeft, restore: anchor)])
    }

    func testSlowTopMoveIsNotASwipe() {
        drag([(0.5, 0.97, 0), (0.45, 0.97, 0.3), (0.3, 0.97, 0.6)])
        XCTAssertEqual(events, [])
    }

    func testTopEdgeDisabled() {
        configure { $0.topEdge = false }
        drag([(0.5, 0.97, 0), (0.7, 0.97, 0.1)])
        XCTAssertEqual(events, [])
    }

    func testEdgeControlsOffKeepsTopEdge() {
        configure { $0.edgeControls = false }
        drag([(0.97, 0.5, 0), (0.97, 0.6, 0.01)])
        drag([(0.5, 0.97, 1), (0.7, 0.97, 1.1)], id: 2)
        XCTAssertEqual(events, [.topSwipe(.topEdgeSwipeRight, restore: anchor)])
    }

    func testTouchStartingMidPadIsIgnored() {
        drag([(0.5, 0.5, 0), (0.97, 0.5, 0.05), (0.97, 0.8, 0.1)])
        XCTAssertEqual(events, [])
    }
}
