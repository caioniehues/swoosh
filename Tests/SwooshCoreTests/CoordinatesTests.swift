import CoreGraphics
import XCTest
@testable import SwooshCore

final class CoordinatesTests: XCTestCase {
    func testFlipUsesPrimaryHeight() {
        // A 200-tall window whose bottom-left y is 100 on a 900-tall primary display.
        // Top-left y of its top edge = 900 - (100 + 200) = 600.
        let bottomLeft = CGRect(x: 50, y: 100, width: 300, height: 200)
        let flipped = Coordinates.flip(bottomLeft, primaryHeight: 900)
        XCTAssertEqual(flipped, CGRect(x: 50, y: 600, width: 300, height: 200))
    }

    func testFlipIsItsOwnInverse() {
        let r = CGRect(x: 12, y: 340, width: 800, height: 123)
        let back = Coordinates.flip(Coordinates.flip(r, primaryHeight: 1080), primaryHeight: 1080)
        XCTAssertEqual(back, r)
    }
}
