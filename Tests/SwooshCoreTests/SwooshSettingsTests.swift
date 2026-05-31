import CoreGraphics
import Foundation
import XCTest
@testable import SwooshCore

final class SwooshSettingsTests: XCTestCase {
    func testDefaults() {
        let s = SwooshSettings.default
        XCTAssertEqual(s.gridRows, 3)
        XCTAssertEqual(s.gridCols, 3)
        XCTAssertTrue(s.hapticsEnabled)
        XCTAssertEqual(s.outerGap, 0)
        XCTAssertEqual(s.commitThreshold, 30)
        XCTAssertEqual(s.diagonalThreshold, 0.4)
    }

    func testValidationClampsEveryField() {
        let wild = SwooshSettings(gridRows: 0, gridCols: 99, hapticsEnabled: false,
                                  outerGap: -5, innerGap: -1, commitThreshold: 0,
                                  diagonalThreshold: 2.0).validated()
        XCTAssertEqual(wild.gridRows, 1, "rows clamp up to 1")
        XCTAssertEqual(wild.gridCols, SwooshSettings.maxGridDimension, "cols clamp to the max")
        XCTAssertEqual(wild.outerGap, 0, "negative gap clamps to 0")
        XCTAssertEqual(wild.innerGap, 0)
        XCTAssertEqual(wild.commitThreshold, 1, accuracy: 1e-9)
        XCTAssertEqual(wild.diagonalThreshold, 0.95, accuracy: 1e-9)
        XCTAssertFalse(wild.hapticsEnabled, "non-clamped fields are preserved")
    }

    func testValidationLeavesValidSettingsUnchanged() {
        let s = SwooshSettings(gridRows: 5, gridCols: 1, outerGap: 8, innerGap: 4)
        XCTAssertEqual(s.validated(), s)
    }

    func testCodableRoundTrip() throws {
        let s = SwooshSettings(gridRows: 4, gridCols: 1, hapticsEnabled: false,
                               outerGap: 12, innerGap: 6, commitThreshold: 25, diagonalThreshold: 0.5)
        let decoded = try JSONDecoder().decode(SwooshSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded, s)
    }

    func testOuterInsets() {
        XCTAssertEqual(SwooshSettings(outerGap: 10).outerInsets, PixelInsets(10))
    }
}
