import CoreGraphics
import XCTest
@testable import SwooshCore

final class SnapClassifierTests: XCTestCase {
    let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)

    func testClassifiesLeftHalf() {
        let frame = SnapEngine.rect(for: .preset(.leftHalf), in: vf)!
        XCTAssertEqual(SnapClassifier.classify(frame: frame, in: vf), .preset(.leftHalf))
    }

    func testClassifiesTopRightQuarter() {
        let frame = SnapEngine.rect(for: .preset(.topRightQuarter), in: vf)!
        XCTAssertEqual(SnapClassifier.classify(frame: frame, in: vf), .preset(.topRightQuarter))
    }

    func testClassifiesMaximize() {
        XCTAssertEqual(SnapClassifier.classify(frame: vf, in: vf), .preset(.maximize))
    }

    func testUnsnappedForArbitraryFrame() {
        let frame = CGRect(x: 123, y: 77, width: 640, height: 480)
        XCTAssertEqual(SnapClassifier.classify(frame: frame, in: vf), .unsnapped)
    }

    func testTolerance() {
        // 1pt off still matches; 5pt off does not (default tolerance 2).
        let base = SnapEngine.rect(for: .preset(.rightHalf), in: vf)!
        let off1 = base.offsetBy(dx: 1, dy: -1)
        let off5 = base.offsetBy(dx: 5, dy: 0)
        XCTAssertEqual(SnapClassifier.classify(frame: off1, in: vf), .preset(.rightHalf))
        XCTAssertEqual(SnapClassifier.classify(frame: off5, in: vf), .unsnapped)
    }
}
