import CoreGraphics
import XCTest
@testable import SwooshCore

final class HoldGridTests: XCTestCase {
    let vf = CGRect(x: 0, y: 0, width: 900, height: 900)

    func testThreeByThreeCorners() {
        XCTAssertEqual(HoldGrid.cell(at: CGPoint(x: 50, y: 50), rows: 3, cols: 3, in: vf),
                       .gridCell(row: 0, col: 0, rows: 3, cols: 3))     // top-left
        XCTAssertEqual(HoldGrid.cell(at: CGPoint(x: 450, y: 450), rows: 3, cols: 3, in: vf),
                       .gridCell(row: 1, col: 1, rows: 3, cols: 3))     // center
        XCTAssertEqual(HoldGrid.cell(at: CGPoint(x: 850, y: 850), rows: 3, cols: 3, in: vf),
                       .gridCell(row: 2, col: 2, rows: 3, cols: 3))     // bottom-right
    }

    func testUltrawideFiveColumn() {
        let wide = CGRect(x: 0, y: 0, width: 1000, height: 800)
        // x = 450 → column 2 of 5; single row.
        XCTAssertEqual(HoldGrid.cell(at: CGPoint(x: 450, y: 400), rows: 1, cols: 5, in: wide),
                       .gridCell(row: 0, col: 2, rows: 1, cols: 5))
    }

    func testOffsetVisibleFrame() {
        let offset = CGRect(x: 100, y: 50, width: 900, height: 900)
        // cursor near the offset origin → top-left cell.
        XCTAssertEqual(HoldGrid.cell(at: CGPoint(x: 150, y: 100), rows: 3, cols: 3, in: offset),
                       .gridCell(row: 0, col: 0, rows: 3, cols: 3))
    }

    func testCursorOutsideCancels() {
        XCTAssertNil(HoldGrid.cell(at: CGPoint(x: -10, y: 400), rows: 3, cols: 3, in: vf))
        XCTAssertNil(HoldGrid.cell(at: CGPoint(x: 2000, y: 400), rows: 3, cols: 3, in: vf))
    }
}
