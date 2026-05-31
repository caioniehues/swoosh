import CoreGraphics
import XCTest
import SwooshCore
import SwooshFixtures

final class ReplayerTests: XCTestCase {
    let band = CGRect(x: 0, y: 0, width: 800, height: 28)

    func input(count: Int = 2, phase: ScrollPhase = .began, continuous: Bool = true,
               cursor: CGPoint = CGPoint(x: 400, y: 14), band hasBand: CGRect? = CGRect(x: 0, y: 0, width: 800, height: 28)) -> RecognizerInput {
        RecognizerInput(contactCount: count, phase: phase, isContinuous: continuous,
                        cursor: cursor, titlebarBand: hasBand)
    }

    /// A fixture recorded with the recognizer's own decisions replays clean.
    func testMatchingFixturePasses() {
        var rec = FixtureRecorder()
        let inputs = [input(phase: .began), input(phase: .changed),
                      input(count: 1), input(continuous: false)]
        for (i, inp) in inputs.enumerated() {
            rec.record(t: Double(i) * 0.016, input: inp, decision: Recognizer.decide(inp))
        }
        let fixture = rec.makeFixture(name: "synthetic", description: "round-trip",
                                      recordedOnOS: "test", capturedAt: "2026-05-31")
        let result = Replayer.replay(fixture)
        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.sampleCount, 4)
        XCTAssertEqual(result.diffs, [])
    }

    /// POSITIVE CONTROL for the harness itself: a fixture whose recorded decision is wrong must
    /// be reported as a diff. If this ever passes silently, the canary is blind.
    func testDetectsRegression() {
        // This input decides .pass, but we record it as .suppress — a planted "regression".
        let passInput = input(count: 1)
        XCTAssertEqual(Recognizer.decide(passInput), .pass)

        let fixture = Fixture(
            meta: .init(name: "planted", description: "wrong baseline", recordedOnOS: "test", capturedAt: "2026-05-31"),
            samples: [Fixture.Sample(t: 0, input: passInput, decision: .suppress)]
        )
        let result = Replayer.replay(fixture)
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.diffs.count, 1)
        XCTAssertEqual(result.diffs.first?.index, 0)
        XCTAssertEqual(result.diffs.first?.expected, .suppress)  // recorded baseline
        XCTAssertEqual(result.diffs.first?.actual, .pass)        // current recognizer
    }

    /// The flat on-disk schema round-trips losslessly through JSON.
    func testCodecRoundTrip() throws {
        var rec = FixtureRecorder()
        rec.record(t: 0, input: input(phase: .began), decision: .suppress, rawContactFrame: [2])
        rec.record(t: 0.1, input: input(cursor: CGPoint(x: 9, y: 999), band: nil), decision: .pass)
        let original = rec.makeFixture(name: "roundtrip", description: "codec",
                                       recordedOnOS: "macOS 26.5", capturedAt: "2026-05-31")
        let decoded = try Fixture.decode(from: original.encoded())
        XCTAssertEqual(decoded, original)
        // The no-band sample reconstructs a nil band.
        XCTAssertNil(decoded.samples[1].input.titlebarBand)
        XCTAssertEqual(decoded.samples[0].rawContactFrame, [2])
    }

    /// A recorded sample reconstructs the exact engine input + decision it was built from.
    func testSampleReconstructsEngineTypes() {
        let inp = input(count: 2, phase: .changed, cursor: CGPoint(x: 123, y: 7))
        let sample = Fixture.Sample(t: 0.05, input: inp, decision: .suppress)
        XCTAssertEqual(sample.input, inp)
        XCTAssertEqual(sample.recordedDecision, .suppress)
    }
}
