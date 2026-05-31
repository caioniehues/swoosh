import CoreGraphics
import XCTest
@testable import SwooshCore

final class DividerLocatorTests: XCTestCase {
    // Two halves of a 1000×800 screen sharing the x=500 edge.
    let left = WindowFrame(id: 1, frame: CGRect(x: 0, y: 0, width: 500, height: 800))
    let right = WindowFrame(id: 2, frame: CGRect(x: 500, y: 0, width: 500, height: 800))

    func testFindsVerticalDivider() {
        let d = DividerLocator.divider(at: CGPoint(x: 500, y: 400), among: [left, right])
        XCTAssertEqual(d, Divider(orientation: .vertical, position: 500,
                                  leading: 1, trailing: 2, spanMin: 0, spanMax: 800))
    }

    func testCursorOutsideBand() {
        // 25 pt away from the x=500 edge (> bandHalfWidth 8) → no divider.
        XCTAssertNil(DividerLocator.divider(at: CGPoint(x: 525, y: 400), among: [left, right]))
    }

    func testFindsHorizontalDivider() {
        let top = WindowFrame(id: 3, frame: CGRect(x: 0, y: 0, width: 1000, height: 400))
        let bottom = WindowFrame(id: 4, frame: CGRect(x: 0, y: 400, width: 1000, height: 400))
        let d = DividerLocator.divider(at: CGPoint(x: 500, y: 400), among: [top, bottom])
        XCTAssertEqual(d?.orientation, .horizontal)
        XCTAssertEqual(d?.leading, 3)
        XCTAssertEqual(d?.trailing, 4)
        XCTAssertEqual(d?.position, 400)
    }

    func testGapBetweenWindowsIsNotADivider() {
        // 200pt gap (400→600) is well beyond edgeTolerance → not a shared edge.
        let a = WindowFrame(id: 1, frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let b = WindowFrame(id: 2, frame: CGRect(x: 600, y: 0, width: 400, height: 800))
        XCTAssertNil(DividerLocator.divider(at: CGPoint(x: 500, y: 400), among: [a, b]))
    }

    func testInsufficientOverlapIsNotADivider() {
        // Edges touch at x=500 but y-overlap is only 20pt (< minOverlap 40).
        let a = WindowFrame(id: 1, frame: CGRect(x: 0, y: 0, width: 500, height: 100))
        let b = WindowFrame(id: 2, frame: CGRect(x: 500, y: 80, width: 500, height: 100))
        XCTAssertNil(DividerLocator.divider(at: CGPoint(x: 500, y: 90), among: [a, b]))
    }
}

final class DividerResolverTests: XCTestCase {
    let left = CGRect(x: 0, y: 0, width: 500, height: 800)
    let right = CGRect(x: 500, y: 0, width: 500, height: 800)

    func testVerticalResize() {
        let (l, r) = DividerResolver.resize(leading: left, trailing: right, orientation: .vertical, to: 600)
        XCTAssertEqual(l, CGRect(x: 0, y: 0, width: 600, height: 800))
        XCTAssertEqual(r, CGRect(x: 600, y: 0, width: 400, height: 800))
    }

    func testVerticalResizeClampsToMinSize() {
        // Drag toward x=20, minSize 100 → leading can't shrink below 100 wide.
        let (l, r) = DividerResolver.resize(leading: left, trailing: right, orientation: .vertical,
                                            to: 20, minSize: 100)
        XCTAssertEqual(l.width, 100, accuracy: 1e-9)
        XCTAssertEqual(r.minX, 100, accuracy: 1e-9)
        XCTAssertEqual(r.width, 900, accuracy: 1e-9)
    }

    func testHorizontalResize() {
        let top = CGRect(x: 0, y: 0, width: 1000, height: 400)
        let bottom = CGRect(x: 0, y: 400, width: 1000, height: 400)
        let (t, b) = DividerResolver.resize(leading: top, trailing: bottom, orientation: .horizontal, to: 300)
        XCTAssertEqual(t, CGRect(x: 0, y: 0, width: 1000, height: 300))
        XCTAssertEqual(b, CGRect(x: 0, y: 300, width: 1000, height: 500))
    }
}
