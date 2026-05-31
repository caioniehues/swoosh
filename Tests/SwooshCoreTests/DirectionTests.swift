import CoreGraphics
import XCTest
@testable import SwooshCore

final class DirectionTests: XCTestCase {
    func testCardinalAxes() {
        // +x = right, +y = up (math convention; callers normalize CG scroll signs).
        XCTAssertEqual(Direction(scrollDelta: CGVector(dx: 10, dy: 0)), .right)
        XCTAssertEqual(Direction(scrollDelta: CGVector(dx: -10, dy: 0)), .left)
        XCTAssertEqual(Direction(scrollDelta: CGVector(dx: 0, dy: 10)), .up)
        XCTAssertEqual(Direction(scrollDelta: CGVector(dx: 0, dy: -10)), .down)
    }

    func testDiagonals() {
        XCTAssertEqual(Direction(scrollDelta: CGVector(dx: 10, dy: 10)), .upRight)
        XCTAssertEqual(Direction(scrollDelta: CGVector(dx: -10, dy: 10)), .upLeft)
        XCTAssertEqual(Direction(scrollDelta: CGVector(dx: 10, dy: -10)), .downRight)
        XCTAssertEqual(Direction(scrollDelta: CGVector(dx: -10, dy: -10)), .downLeft)
    }

    func testNearAxisIsNotDiagonal() {
        // minor/major = 1/10 = 0.1 < 0.4 → dominant axis wins.
        XCTAssertEqual(Direction(scrollDelta: CGVector(dx: 10, dy: 1)), .right)
        XCTAssertEqual(Direction(scrollDelta: CGVector(dx: 1, dy: 10)), .up)
    }

    func testDiagonalThresholdBoundary() {
        // minor/major = 5/10 = 0.5 ≥ 0.4 → diagonal.
        XCTAssertEqual(Direction(scrollDelta: CGVector(dx: 10, dy: 5)), .upRight)
        // exactly at threshold 0.4 counts as diagonal.
        XCTAssertEqual(Direction(scrollDelta: CGVector(dx: 10, dy: 4)), .upRight)
        // just under (0.39) is axial.
        XCTAssertEqual(Direction(scrollDelta: CGVector(dx: 100, dy: 39)), .right)
    }

    func testCustomThreshold() {
        // With a stricter threshold, 0.5 no longer counts as diagonal.
        XCTAssertEqual(Direction(scrollDelta: CGVector(dx: 10, dy: 5), diagonalThreshold: 0.6),
                       .right)
    }

    func testZeroVectorIsNil() {
        XCTAssertNil(Direction(scrollDelta: CGVector(dx: 0, dy: 0)))
    }
}
