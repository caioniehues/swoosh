import CoreGraphics
import XCTest
@testable import SwooshCore

final class SnapEngineTests: XCTestCase {
    // A non-origin visible frame catches bugs that an origin-anchored frame would hide.
    let vf = CGRect(x: 100, y: 50, width: 1000, height: 800)
    let acc = 1e-9

    func assertRect(_ r: CGRect?, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                    file: StaticString = #filePath, line: UInt = #line) {
        guard let r else { return XCTFail("expected a rect, got nil", file: file, line: line) }
        XCTAssertEqual(r.minX, x, accuracy: acc, "x", file: file, line: line)
        XCTAssertEqual(r.minY, y, accuracy: acc, "y", file: file, line: line)
        XCTAssertEqual(r.width, w, accuracy: acc, "w", file: file, line: line)
        XCTAssertEqual(r.height, h, accuracy: acc, "h", file: file, line: line)
    }

    func testLeftHalf() {
        assertRect(SnapEngine.rect(for: .preset(.leftHalf), in: vf), 100, 50, 500, 800)
    }

    func testRightHalf() {
        assertRect(SnapEngine.rect(for: .preset(.rightHalf), in: vf), 600, 50, 500, 800)
    }

    func testTopRightQuarter() {
        // x = 100 + 0.5*1000 = 600 ; y = 50 ; w/h = 500/400
        assertRect(SnapEngine.rect(for: .preset(.topRightQuarter), in: vf), 600, 50, 500, 400)
    }

    func testBottomLeftQuarter() {
        assertRect(SnapEngine.rect(for: .preset(.bottomLeftQuarter), in: vf), 100, 450, 500, 400)
    }

    func testThirds() {
        assertRect(SnapEngine.rect(for: .preset(.leftThird), in: vf), 100, 50, 1000.0 / 3, 800)
        assertRect(SnapEngine.rect(for: .preset(.centerThird), in: vf),
                   100 + 1000.0 / 3, 50, 1000.0 / 3, 800)
        assertRect(SnapEngine.rect(for: .preset(.rightThird), in: vf),
                   100 + 2000.0 / 3, 50, 1000.0 / 3, 800)
    }

    func testMaximizeEqualsFullScreen() {
        let a = SnapEngine.rect(for: .preset(.maximize), in: vf)
        let b = SnapEngine.rect(for: .fullScreen, in: vf)
        XCTAssertEqual(a, b)
        assertRect(a, 100, 50, 1000, 800)
    }

    // The headline capability: an ultrawide N-column layout is just grid arithmetic.
    func testUltrawideFiveColumn() {
        // column 2 of 5: x = 100 + (2/5)*1000 = 500 ; w = 200 ; full height.
        assertRect(SnapEngine.rect(for: .gridCell(row: 0, col: 2, rows: 1, cols: 5), in: vf),
                   500, 50, 200, 800)
    }

    func testGridBottomLeftOfTwoByTwo() {
        // row 1, col 0 of 2×2 → bottom-left quarter.
        assertRect(SnapEngine.rect(for: .gridCell(row: 1, col: 0, rows: 2, cols: 2), in: vf),
                   100, 450, 500, 400)
    }

    func testGridClampsOutOfRange() {
        // col 9 in a 2-col grid clamps to col 1 (rightmost).
        assertRect(SnapEngine.rect(for: .gridCell(row: 0, col: 9, rows: 1, cols: 2), in: vf),
                   600, 50, 500, 800)
    }

    func testGridNonPositiveDimsFallBackToFull() {
        let f = SnapEngine.gridFraction(row: 0, col: 0, rows: 0, cols: 3)
        XCTAssertEqual(f, .full)
    }

    func testInsetsShrinkSymmetrically() {
        let f = FractionalRect(x: 0, y: 0, w: 0.5, h: 1, inset: PixelInsets(10))
        // leftHalf 500×800 inset 10 on all sides → origin +10,+10 ; size −20 each.
        assertRect(SnapEngine.rect(for: f, in: vf), 110, 60, 480, 780)
    }

    func testAsymmetricInsets() {
        let f = FractionalRect(x: 0, y: 0, w: 1, h: 1,
                               inset: PixelInsets(top: 5, left: 10, bottom: 15, right: 20))
        // full 1000×800 → x 100+10, y 50+5, w 1000-30, h 800-20
        assertRect(SnapEngine.rect(for: f, in: vf), 110, 55, 970, 780)
    }

    func testRestoreHasNoFraction() {
        XCTAssertNil(SnapEngine.fraction(for: .restore))
        XCTAssertNil(SnapEngine.rect(for: .restore, in: vf))
    }
}
