import CoreGraphics
import XCTest
@testable import SwooshCore

final class SwipeResolverTests: XCTestCase {
    func testHalves() {
        XCTAssertEqual(SwipeResolver.target(for: .left, currentState: .unsnapped), .preset(.leftHalf))
        XCTAssertEqual(SwipeResolver.target(for: .right, currentState: .unsnapped), .preset(.rightHalf))
    }

    func testUpTogglesToFullScreenOnlyFromTopHalf() {
        XCTAssertEqual(SwipeResolver.target(for: .up, currentState: .unsnapped), .preset(.topHalf))
        XCTAssertEqual(SwipeResolver.target(for: .up, currentState: .preset(.topHalf)), .fullScreen)
        // From any OTHER preset, ↑ goes to top half (not fullscreen).
        XCTAssertEqual(SwipeResolver.target(for: .up, currentState: .preset(.leftHalf)), .preset(.topHalf))
    }

    func testDownRestoresWhenSnapped() {
        XCTAssertEqual(SwipeResolver.target(for: .down, currentState: .unsnapped), .preset(.bottomHalf))
        XCTAssertEqual(SwipeResolver.target(for: .down, currentState: .preset(.leftHalf)), .restore)
        XCTAssertEqual(SwipeResolver.target(for: .down, currentState: .preset(.bottomHalf)), .restore)
    }

    func testDiagonalsToQuarters() {
        XCTAssertEqual(SwipeResolver.target(for: .upLeft, currentState: .unsnapped), .preset(.topLeftQuarter))
        XCTAssertEqual(SwipeResolver.target(for: .upRight, currentState: .unsnapped), .preset(.topRightQuarter))
        XCTAssertEqual(SwipeResolver.target(for: .downLeft, currentState: .unsnapped), .preset(.bottomLeftQuarter))
        XCTAssertEqual(SwipeResolver.target(for: .downRight, currentState: .unsnapped), .preset(.bottomRightQuarter))
    }
}

final class SwipeGestureTests: XCTestCase {
    func testAccumulatesAndCommits() {
        var g = SwipeGesture(commitThreshold: 30)
        g.add(phase: .began, delta: CGVector(dx: 10, dy: 0))
        XCTAssertNil(g.committedDirection(), "below threshold (10 < 30)")
        g.add(phase: .changed, delta: CGVector(dx: 10, dy: 0))
        g.add(phase: .changed, delta: CGVector(dx: 15, dy: 0))   // accumulated dx = 35
        XCTAssertEqual(g.magnitude, 35, accuracy: 1e-9)
        XCTAssertEqual(g.committedDirection(), .right)
    }

    func testChangedBeforeBeganIsIgnored() {
        var g = SwipeGesture(commitThreshold: 5)
        g.add(phase: .changed, delta: CGVector(dx: 100, dy: 0))  // no active gesture yet
        XCTAssertEqual(g.magnitude, 0)
        XCTAssertNil(g.committedDirection())
    }

    func testEndedDoesNotAccumulateAndResetClears() {
        var g = SwipeGesture(commitThreshold: 5)
        g.add(phase: .began, delta: CGVector(dx: 0, dy: 40))
        g.add(phase: .ended, delta: CGVector(dx: 999, dy: 0))    // ended must not accumulate
        XCTAssertEqual(g.committedDirection(), .up)
        g.reset()
        XCTAssertEqual(g.magnitude, 0)
        XCTAssertFalse(g.isActive)
    }

    func testDiagonalCommit() {
        var g = SwipeGesture(commitThreshold: 10)
        g.add(phase: .began, delta: CGVector(dx: 30, dy: 30))
        XCTAssertEqual(g.committedDirection(), .upRight)
    }
}
