import Foundation
import SwooshCore

/// One disagreement between a fixture's recorded decision and what the current recognizer
/// produces — i.e. a regression.
public struct ReplayDiff: Equatable, Sendable {
    public let index: Int
    public let expected: Decision   // recorded baseline
    public let actual: Decision     // current recognizer
    public let input: RecognizerInput

    public init(index: Int, expected: Decision, actual: Decision, input: RecognizerInput) {
        self.index = index
        self.expected = expected
        self.actual = actual
        self.input = input
    }
}

/// The result of replaying one fixture.
public struct ReplayResult: Equatable, Sendable {
    public let fixtureName: String
    public let sampleCount: Int
    public let diffs: [ReplayDiff]

    public var passed: Bool { diffs.isEmpty }

    public init(fixtureName: String, sampleCount: Int, diffs: [ReplayDiff]) {
        self.fixtureName = fixtureName
        self.sampleCount = sampleCount
        self.diffs = diffs
    }
}

/// The headless replayer (DERISK §3). Feeds a fixture's recorded inputs back through the pure
/// `Recognizer` — **no trackpad, no AX, no original apps** — and diffs the produced decisions
/// against the recorded baseline. A diff is a regression. This is what turns "Layers 1–3 are
/// manual-test-only" into "Layers 1–3 are covered by replayable assertions," and it runs in CI
/// on every PR with no special hardware.
public enum Replayer {
    /// Replay a single fixture in memory.
    public static func replay(_ fixture: Fixture) -> ReplayResult {
        var diffs: [ReplayDiff] = []
        for (i, sample) in fixture.samples.enumerated() {
            let actual = Recognizer.decide(sample.input)
            let expected = sample.recordedDecision
            if actual != expected {
                diffs.append(
                    ReplayDiff(index: i, expected: expected, actual: actual, input: sample.input)
                )
            }
        }
        return ReplayResult(
            fixtureName: fixture.meta.name,
            sampleCount: fixture.samples.count,
            diffs: diffs
        )
    }

    /// Load and decode a single fixture file.
    public static func load(contentsOf url: URL) throws -> Fixture {
        try Fixture.decode(from: Data(contentsOf: url))
    }

    /// Load every `*.json` fixture in `directory`, sorted by filename for deterministic order.
    public static func loadCorpus(in directory: URL) throws -> [Fixture] {
        let urls = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try urls.map { try load(contentsOf: $0) }
    }

    /// Replay the whole corpus — the body of the macOS-beta canary (DERISK §4).
    public static func replayCorpus(in directory: URL) throws -> [ReplayResult] {
        try loadCorpus(in: directory).map(replay)
    }
}
