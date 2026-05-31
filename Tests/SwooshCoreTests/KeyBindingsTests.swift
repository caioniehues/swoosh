import XCTest
@testable import SwooshCore

final class KeyBindingsTests: XCTestCase {
    let mod: KeyModifiers = .controlOption

    func testNumpadGridMapping() {
        // 1 = bottom-left, 9 = top-right, 5 = center (SPEC §4.5).
        XCTAssertEqual(KeyBindings.numpadGridCell(1), .gridCell(row: 2, col: 0, rows: 3, cols: 3))
        XCTAssertEqual(KeyBindings.numpadGridCell(3), .gridCell(row: 2, col: 2, rows: 3, cols: 3))
        XCTAssertEqual(KeyBindings.numpadGridCell(5), .gridCell(row: 1, col: 1, rows: 3, cols: 3))
        XCTAssertEqual(KeyBindings.numpadGridCell(7), .gridCell(row: 0, col: 0, rows: 3, cols: 3))
        XCTAssertEqual(KeyBindings.numpadGridCell(9), .gridCell(row: 0, col: 2, rows: 3, cols: 3))
        XCTAssertNil(KeyBindings.numpadGridCell(0))
        XCTAssertNil(KeyBindings.numpadGridCell(10))
    }

    func testArrowAndWASDBindings() {
        XCTAssertEqual(KeyBindings.action(for: KeyChord(mod, .left)), .swipe(.left))
        XCTAssertEqual(KeyBindings.action(for: KeyChord(mod, .letter("a"))), .swipe(.left))
        XCTAssertEqual(KeyBindings.action(for: KeyChord(mod, .up)), .swipe(.up))
        XCTAssertEqual(KeyBindings.action(for: KeyChord(mod, .letter("w"))), .swipe(.up))
    }

    func testExplicitBindings() {
        XCTAssertEqual(KeyBindings.action(for: KeyChord(mod, .digit(0))), .snap(.fullScreen))
        XCTAssertEqual(KeyBindings.action(for: KeyChord(mod, .digit(5))),
                       .snap(.gridCell(row: 1, col: 1, rows: 3, cols: 3)))
        XCTAssertEqual(KeyBindings.action(for: KeyChord(mod, .return)), .restore)
        XCTAssertEqual(KeyBindings.action(for: KeyChord(mod, .letter("f"))), .exitFullscreen)
    }

    func testUnboundChordReturnsNil() {
        // No modifier → not a Swoosh shortcut.
        XCTAssertNil(KeyBindings.action(for: KeyChord([], .left)))
        // Wrong modifier (just command) → unbound.
        XCTAssertNil(KeyBindings.action(for: KeyChord(.command, .left)))
    }

    func testEveryDefaultDigitIsBound() {
        for d in 0 ... 9 {
            XCTAssertNotNil(KeyBindings.action(for: KeyChord(mod, .digit(d))), "digit \(d) unbound")
        }
    }
}
