import CoreGraphics
import Foundation
import SwooshCore

/// A self-contained capture of one gesture or short session (DERISK §2). On disk it is a
/// single JSON file in `tests/fixtures/`. The schema is deliberately **flat and explicit**
/// (scalar fields, not nested `CGRect` Codable) so a non-developer can record and hand-edit
/// one with no toolchain — the lowest-bar community contribution.
public struct Fixture: Codable, Equatable, Sendable {
    /// Bumped when the on-disk schema changes incompatibly; the replayer can then refuse or migrate.
    public var schemaVersion: Int
    public var meta: Meta
    public var samples: [Sample]

    public init(schemaVersion: Int = Fixture.currentSchemaVersion, meta: Meta, samples: [Sample]) {
        self.schemaVersion = schemaVersion
        self.meta = meta
        self.samples = samples
    }

    public static let currentSchemaVersion = 1
}

extension Fixture {
    public struct Meta: Codable, Equatable, Sendable {
        public var name: String
        public var description: String
        /// e.g. "macOS 26.5" — so a replay failure can be attributed to an OS.
        public var recordedOnOS: String
        /// A plain date string (e.g. "2026-05-31"); a string, not `Date`, keeps JSON stable and TZ-free.
        public var capturedAt: String

        public init(name: String, description: String, recordedOnOS: String, capturedAt: String) {
            self.name = name
            self.description = description
            self.recordedOnOS = recordedOnOS
            self.capturedAt = capturedAt
        }
    }

    /// One scroll event with the time-aligned context the suppress/pass gate saw (Layers 1–3a)
    /// plus the **recorded-correct** decision (the golden baseline the replayer diffs against).
    public struct Sample: Codable, Equatable, Sendable {
        /// Seconds from the start of the fixture (time alignment, DERISK §2).
        public var t: Double
        // Layer 2 (finger count) + Layer 1 (scroll event) + Layer 3a (fast geometry):
        public var contactCount: Int
        /// `ScrollPhase` raw value (1 = began, 2 = changed, 128 = mayBegin, …).
        public var phase: Int
        public var isContinuous: Bool
        public var cursorX: Double
        public var cursorY: Double
        // Titlebar band: all four present together, or all omitted for "no titlebar under cursor".
        public var bandX: Double?
        public var bandY: Double?
        public var bandW: Double?
        public var bandH: Double?
        /// The recorded decision: "pass" or "suppress" (the baseline).
        public var decision: String
        /// Optional raw Layer-2 contact frame. Recording it alongside the decoded count means a
        /// future struct-layout change reads as "raw present, decode mismatched" rather than a
        /// silent wrong answer (DERISK §2 caveat).
        public var rawContactFrame: [Int]?

        public init(
            t: Double,
            contactCount: Int,
            phase: Int,
            isContinuous: Bool,
            cursorX: Double,
            cursorY: Double,
            bandX: Double? = nil,
            bandY: Double? = nil,
            bandW: Double? = nil,
            bandH: Double? = nil,
            decision: String,
            rawContactFrame: [Int]? = nil
        ) {
            self.t = t
            self.contactCount = contactCount
            self.phase = phase
            self.isContinuous = isContinuous
            self.cursorX = cursorX
            self.cursorY = cursorY
            self.bandX = bandX
            self.bandY = bandY
            self.bandW = bandW
            self.bandH = bandH
            self.decision = decision
            self.rawContactFrame = rawContactFrame
        }

        /// Build a sample from the engine's own input/decision types (used by the recorder).
        public init(
            t: Double,
            input: RecognizerInput,
            decision: Decision,
            rawContactFrame: [Int]? = nil
        ) {
            self.init(
                t: t,
                contactCount: input.contactCount,
                phase: input.phase.rawValue,
                isContinuous: input.isContinuous,
                cursorX: Double(input.cursor.x),
                cursorY: Double(input.cursor.y),
                bandX: input.titlebarBand.map { Double($0.minX) },
                bandY: input.titlebarBand.map { Double($0.minY) },
                bandW: input.titlebarBand.map { Double($0.width) },
                bandH: input.titlebarBand.map { Double($0.height) },
                decision: decision.rawValue,
                rawContactFrame: rawContactFrame
            )
        }

        /// Reconstruct the recognizer input this sample represents.
        public var input: RecognizerInput {
            let band: CGRect? = {
                guard let x = bandX, let y = bandY, let w = bandW, let h = bandH else { return nil }
                return CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(w), height: CGFloat(h))
            }()
            return RecognizerInput(
                contactCount: contactCount,
                phase: ScrollPhase(rawValue: phase) ?? .none,
                isContinuous: isContinuous,
                cursor: CGPoint(x: CGFloat(cursorX), y: CGFloat(cursorY)),
                titlebarBand: band
            )
        }

        /// The recorded baseline decision (defaults to `.pass` for an unknown string).
        public var recordedDecision: Decision {
            Decision(rawValue: decision) ?? .pass
        }
    }
}

// MARK: - Codec

extension Fixture {
    /// Decode a fixture from JSON.
    public static func decode(from data: Data) throws -> Fixture {
        try JSONDecoder().decode(Fixture.self, from: data)
    }

    /// Encode to JSON with stable key ordering and pretty printing, so a re-recorded fixture
    /// produces a minimal, reviewable `git diff`.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
