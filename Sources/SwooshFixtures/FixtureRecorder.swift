import Foundation
import SwooshCore

/// Accumulates time-aligned samples during a live capture session, then emits a `Fixture`
/// (DERISK §2 "capture mode"). Appending is cheap and non-allocating-bursty, so the live tap
/// path can record without blocking — the actual disk flush happens off the tap thread.
///
/// In M1 this is the data sink the system layers (SwooshKit) will call; here it is fully
/// exercised by the replayer round-trip tests.
public struct FixtureRecorder: Sendable {
    public private(set) var samples: [Fixture.Sample] = []

    public init() {}

    /// Record one event: the gate input the tap saw and the decision it produced.
    public mutating func record(
        t: Double,
        input: RecognizerInput,
        decision: Decision,
        rawContactFrame: [Int]? = nil
    ) {
        samples.append(
            Fixture.Sample(t: t, input: input, decision: decision, rawContactFrame: rawContactFrame)
        )
    }

    /// Seal the recorded samples into a `Fixture`.
    public func makeFixture(
        name: String,
        description: String,
        recordedOnOS: String,
        capturedAt: String
    ) -> Fixture {
        Fixture(
            meta: .init(
                name: name,
                description: description,
                recordedOnOS: recordedOnOS,
                capturedAt: capturedAt
            ),
            samples: samples
        )
    }

    /// Drop all recorded samples (start a fresh capture).
    public mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }
}
