import CoreGraphics
import XCTest
@testable import Toolbelt

final class InputTapTests: XCTestCase {
    private func has(_ mask: CGEventMask, _ t: CGEventType) -> Bool { mask & (1 << CGEventMask(t.rawValue)) != 0 }

    func testMaskCoversOnlyEnabledFeatures() {
        XCTAssertEqual(InputTap.mask(for: .init()), 0)
        let dock = InputTap.mask(for: .init(dockClick: true))
        XCTAssertTrue(has(dock, .leftMouseDown) && has(dock, .leftMouseUp))
        XCTAssertFalse(has(dock, .keyDown) || has(dock, .leftMouseDragged) || has(dock, .otherMouseDown))
        let middle = InputTap.mask(for: .init(middle: true))
        XCTAssertTrue(has(middle, .otherMouseDown) && has(middle, .otherMouseDragged) && has(middle, .otherMouseUp))
        XCTAssertFalse(has(middle, .leftMouseDown) || has(middle, .keyDown))
        let pad = InputTap.mask(for: .init(trackpadPress: true))
        XCTAssertTrue(has(pad, .leftMouseDragged) && has(pad, .otherMouseDown))
        let sw = InputTap.mask(for: .init(switcher: true))
        XCTAssertTrue(has(sw, .keyDown) && has(sw, .flagsChanged) && has(sw, .leftMouseDown))
    }

    func testDragThreshold() {
        XCTAssertFalse(WindowMover.isDrag(from: .zero, to: CGPoint(x: 3, y: 2)))
        XCTAssertTrue(WindowMover.isDrag(from: .zero, to: CGPoint(x: 4, y: 3)))
    }

    func testFinderAlternate() {
        let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        XCTAssertEqual(DockClick.finderAlternate(itemURL: finder, isApp: true, enabled: true, path: "/Applications/Safari.app")?.path,
                       "/Applications/Safari.app")
        XCTAssertNil(DockClick.finderAlternate(itemURL: finder, isApp: true, enabled: false, path: "/Applications/Safari.app"))
        XCTAssertNil(DockClick.finderAlternate(itemURL: finder, isApp: true, enabled: true, path: ""))
        XCTAssertNil(DockClick.finderAlternate(itemURL: URL(fileURLWithPath: "/Applications/Mail.app"), isApp: true,
                                               enabled: true, path: "/Applications/Safari.app"))
    }
}

final class TapDetectorTests: XCTestCase {
    private let three: [(x: Float, y: Float)] = [(0.4, 0.5), (0.5, 0.5), (0.6, 0.5)]

    private func run(_ frames: [([(x: Float, y: Float)], TimeInterval, Bool)]) -> Bool {
        var d = TapDetector()
        var fired = false
        for (points, t, button) in frames where d.frame(points, at: t, buttonDown: button) { fired = true }
        return fired
    }

    func testLightThreeFingerTapFires() {
        XCTAssertTrue(run([(three, 0, false), (three, 0.08, false), ([], 0.12, false)]))
    }

    func testFingersArrivingOneByOneStillTap() {
        XCTAssertTrue(run([(Array(three.prefix(1)), 0, false), (Array(three.prefix(2)), 0.02, false),
                           (three, 0.04, false), ([], 0.15, false)]))
    }

    func testHoldDoesNotFire() {
        XCTAssertFalse(run([(three, 0, false), (three, 0.3, false), ([], 0.4, false)]))
    }

    func testMovingFingersDoNotFire() {
        let moved = three.map { (x: $0.x + 0.05, y: $0.y) }
        XCTAssertFalse(run([(three, 0, false), (moved, 0.05, false), ([], 0.1, false)]))
    }

    func testPressDoesNotFire() {
        XCTAssertFalse(run([(three, 0, false), (three, 0.05, true), ([], 0.1, false)]))
    }

    func testTwoAndFourFingersDoNotFire() {
        XCTAssertFalse(run([(Array(three.prefix(2)), 0, false), ([], 0.1, false)]))
        XCTAssertFalse(run([(three + [(0.7, 0.5)], 0, false), ([], 0.1, false)]))
    }
}

final class SwitcherTests: XCTestCase {
    func testOrderIsMostRecentFirstThenLaunchOrder() {
        XCTAssertEqual(AppSwitcher.order(running: [1, 2, 3, 4], history: [3, 9, 1]), [3, 1, 2, 4], "dead pid 9 dropped")
        XCTAssertEqual(AppSwitcher.order(running: [5], history: []), [5])
    }

    func testInitialSelectionLikeCommandTab() {
        XCTAssertEqual(AppSwitcher.initialSelection(order: [3, 1, 2], front: 3, backward: false), 1, "previous app")
        XCTAssertEqual(AppSwitcher.initialSelection(order: [3, 1, 2], front: 3, backward: true), 2, "⌘⇧⇥ starts at the end")
        XCTAssertEqual(AppSwitcher.initialSelection(order: [3], front: 3, backward: false), 0)
        XCTAssertEqual(AppSwitcher.initialSelection(order: [3, 1], front: 99, backward: false), 0, "frontmost not listed")
    }

    @MainActor func testInputPrefsDefaultsAndPersist() {
        let d = UserDefaults(suiteName: "tb-\(UUID().uuidString)")!
        let p = Prefs(defaults: d)
        XCTAssertTrue(p.switcher && p.dockMiddleQuit && p.middleDragMove)
        XCTAssertFalse(p.finderOpensApp)
        XCTAssertEqual(p.trackpadMiddle, .standard)
        XCTAssertEqual(p.inputFeatures, .init(dockClick: true, middle: true, trackpadPress: true, switcher: true))
        p.trackpadMiddle = .lighter
        p.finderAppPath = "/Applications/Safari.app"
        let q = Prefs(defaults: d)
        XCTAssertEqual(q.trackpadMiddle, .lighter)
        XCTAssertEqual(q.finderAppPath, "/Applications/Safari.app")
    }
}
