import XCTest
import SwooshCore
import SwooshFixtures

/// Exercises the on-disk corpus in `fixtures/` (DERISK §2). This is the assertion that runs in
/// CI on every PR and, replayed wholesale, forms the macOS-beta canary (DERISK §4).
final class CorpusTests: XCTestCase {
    /// Locate `fixtures/` relative to this source file, so it works locally and in CI without
    /// any working-directory assumptions. (Top-level `fixtures/`, not `tests/fixtures/`, to avoid
    /// a case-collision with SwiftPM's `Tests/` on case-insensitive filesystems — see DERISK §2.)
    var corpusDir: URL {
        URL(fileURLWithPath: #filePath)        // .../Tests/SwooshFixturesTests/CorpusTests.swift
            .deletingLastPathComponent()       // .../Tests/SwooshFixturesTests
            .deletingLastPathComponent()       // .../Tests
            .deletingLastPathComponent()       // repo root
            .appendingPathComponent("fixtures")
    }

    func testCorpusLoads() throws {
        let corpus = try Replayer.loadCorpus(in: corpusDir)
        XCTAssertGreaterThanOrEqual(corpus.count, 5, "expected the committed fixture corpus")
        for fixture in corpus {
            XCTAssertFalse(fixture.samples.isEmpty, "\(fixture.meta.name) has no samples")
            XCTAssertEqual(fixture.schemaVersion, Fixture.currentSchemaVersion)
        }
    }

    /// The whole corpus replays clean against the current recognizer. A failure here is the
    /// regression signal — it prints the offending fixture, sample index, and expected/actual.
    func testCorpusReplaysClean() throws {
        let results = try Replayer.replayCorpus(in: corpusDir)
        for result in results where !result.passed {
            for d in result.diffs {
                XCTFail("[\(result.fixtureName)] sample \(d.index): expected \(d.expected), got \(d.actual)")
            }
        }
        XCTAssertTrue(results.allSatisfy(\.passed))
    }

    /// The corpus must exercise BOTH branches — otherwise an all-pass corpus would "succeed"
    /// against a recognizer that never suppresses anything.
    func testCorpusCoversBothDecisions() throws {
        let corpus = try Replayer.loadCorpus(in: corpusDir)
        let decisions = corpus.flatMap { $0.samples.map(\.recordedDecision) }
        XCTAssertTrue(decisions.contains(.suppress), "corpus has no suppress case")
        XCTAssertTrue(decisions.contains(.pass), "corpus has no pass case")
    }
}
