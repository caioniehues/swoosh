import CoreGraphics
import XCTest
@testable import SwooshCore

final class RecognizerTests: XCTestCase {
    // A titlebar band: x 0…800, y 0…28 (top-left origin), cursor at (400, 14) is inside.
    let band = CGRect(x: 0, y: 0, width: 800, height: 28)
    let inside = CGPoint(x: 400, y: 14)
    let below = CGPoint(x: 400, y: 200)

    func input(count: Int = 2, phase: ScrollPhase = .began, continuous: Bool = true,
               cursor: CGPoint? = nil, band hasBand: CGRect?? = nil) -> RecognizerInput {
        RecognizerInput(
            contactCount: count,
            phase: phase,
            isContinuous: continuous,
            cursor: cursor ?? inside,
            titlebarBand: hasBand ?? band
        )
    }

    func testSuppressesTwoFingerTitlebarPan() {
        XCTAssertEqual(Recognizer.decide(input(phase: .began)), .suppress)
        XCTAssertEqual(Recognizer.decide(input(phase: .changed)), .suppress)
    }

    func testPassesDiscreteMouseWheel() {
        // IsContinuous == false → never our gesture, regardless of everything else.
        XCTAssertEqual(Recognizer.decide(input(continuous: false)), .pass)
    }

    func testPassesWrongContactCount() {
        XCTAssertEqual(Recognizer.decide(input(count: 1)), .pass)
        XCTAssertEqual(Recognizer.decide(input(count: 3)), .pass)
        XCTAssertEqual(Recognizer.decide(input(count: 0)), .pass)
    }

    func testNeverDependsOnMayBegin() {
        // FB9724671: mayBegin (128) was removed in Monterey; it must not trigger suppression.
        XCTAssertEqual(Recognizer.decide(input(phase: .mayBegin)), .pass)
        XCTAssertEqual(Recognizer.decide(input(phase: .ended)), .pass)
        XCTAssertEqual(Recognizer.decide(input(phase: .none)), .pass)
    }

    func testPassesWhenCursorOutsideBand() {
        XCTAssertEqual(Recognizer.decide(input(cursor: below)), .pass)
    }

    func testNilBandDegradesToPass() {
        // A cache miss (nil band) must degrade to pass — never block to recompute.
        XCTAssertEqual(Recognizer.decide(input(band: .some(nil))), .pass)
    }
}
