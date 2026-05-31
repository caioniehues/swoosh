import CoreGraphics
import XCTest
@testable import SwooshCore

final class FrameHistoryTests: XCTestCase {
    func rect(_ i: CGFloat) -> CGRect { CGRect(x: i, y: i, width: i, height: i) }

    func testPushPopWalksBackMostRecentFirst() {
        var h = FrameHistory(capacity: 4)
        h.push(rect(1))
        h.push(rect(2))
        h.push(rect(3))
        XCTAssertEqual(h.count, 3)
        XCTAssertEqual(h.popPrevious(), rect(3))
        XCTAssertEqual(h.popPrevious(), rect(2))
        XCTAssertEqual(h.popPrevious(), rect(1))
        XCTAssertNil(h.popPrevious())
    }

    func testCapacityEvictsOldest() {
        var h = FrameHistory(capacity: 4)
        for i in 1...5 { h.push(rect(CGFloat(i))) }   // push 1..5, capacity 4 → keeps 2..5
        XCTAssertEqual(h.count, 4)
        XCTAssertEqual(h.popPrevious(), rect(5))
        XCTAssertEqual(h.popPrevious(), rect(4))
        XCTAssertEqual(h.popPrevious(), rect(3))
        XCTAssertEqual(h.popPrevious(), rect(2))
        XCTAssertNil(h.popPrevious(), "frame 1 was evicted by the depth-4 bound")
    }

    func testPeekDoesNotRemove() {
        var h = FrameHistory(capacity: 2)
        h.push(rect(7))
        XCTAssertEqual(h.peek(), rect(7))
        XCTAssertEqual(h.count, 1)
    }

    func testEmptyState() {
        var h = FrameHistory()
        XCTAssertTrue(h.isEmpty)
        XCTAssertNil(h.peek())
        XCTAssertNil(h.popPrevious())
        XCTAssertEqual(h.capacity, 4, "default depth is 4 (SPEC §4.6)")
    }
}
