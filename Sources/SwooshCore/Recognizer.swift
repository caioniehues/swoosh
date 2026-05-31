import CoreGraphics

/// Scroll phase, mirroring `kCGScrollPhase*`. **`mayBegin` (128) must never be depended on**
/// — it was silently removed in Monterey (FB9724671) and broke Swish. Suppression keys off
/// `began`/`changed` only (SPEC §6.2 / DERISK §1).
public enum ScrollPhase: Int, Sendable, Codable, Equatable {
    case none = 0
    case began = 1
    case changed = 2
    case ended = 4
    case cancelled = 8
    case mayBegin = 128
}

/// The synchronous inputs the suppress/pass gate sees on the tap thread — exactly the data
/// that must be available without an AX hit-test (SPEC §6.2). A fixture records one of these
/// per scroll event (DERISK §2, Layer 3a) so the replayer can re-derive the decision headlessly.
public struct RecognizerInput: Sendable, Codable, Equatable {
    /// Active contact count from the finger-count source (Layer 2).
    public var contactCount: Int
    /// `kCGScrollWheelEventScrollPhase`.
    public var phase: ScrollPhase
    /// `kCGScrollWheelEventIsContinuous`: false = discrete mouse wheel → always pass.
    public var isContinuous: Bool
    /// Cursor location at the event (AX global, top-left).
    public var cursor: CGPoint
    /// Fast-geometry result: the titlebar band of the frontmost standard window under the
    /// cursor, or `nil` if none. This is the only geometry the gate consults — never AX.
    public var titlebarBand: CGRect?

    public init(
        contactCount: Int,
        phase: ScrollPhase,
        isContinuous: Bool,
        cursor: CGPoint,
        titlebarBand: CGRect?
    ) {
        self.contactCount = contactCount
        self.phase = phase
        self.isContinuous = isContinuous
        self.cursor = cursor
        self.titlebarBand = titlebarBand
    }
}

/// What the recognizer decided for a single scroll event.
public enum Decision: String, Sendable, Codable, Equatable {
    /// Return the event unchanged — normal scrolling.
    case pass
    /// Consume the event (return `nil` from the tap callback) — a titlebar gesture.
    case suppress
}

/// The suppress/pass gate (SPEC §6.2) — the load-bearing S1 logic, extracted as a pure
/// function so it is identical in the live tap callback and in the headless replayer
/// (DERISK §3). It is the seam that turns "Layers 1–3 are manual-test-only" into "Layers 1–3
/// are covered by replayable assertions."
///
/// A swallowed event cannot be un-swallowed, so the decision is synchronous and conservative:
/// **suppress only if all three conditions hold**, and any miss (including a cache miss that
/// makes `titlebarBand` nil) degrades to `pass`, never to "compute synchronously."
public enum Recognizer {
    public static func decide(_ input: RecognizerInput) -> Decision {
        // 0. Discrete mouse wheels (IsContinuous == 0) are never our gesture.
        guard input.isContinuous else { return .pass }
        // 1. Exactly two active contacts.
        guard input.contactCount == 2 else { return .pass }
        // 2. Scroll phase is Began or Changed — never MayBegin (FB9724671).
        guard input.phase == .began || input.phase == .changed else { return .pass }
        // 3. Fast geometry places the cursor inside a titlebar band. A nil band (no titlebar,
        //    or a stale/empty cache) degrades to pass — we never block to recompute.
        guard let band = input.titlebarBand, band.contains(input.cursor) else { return .pass }
        return .suppress
    }
}
