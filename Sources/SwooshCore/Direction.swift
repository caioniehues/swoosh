import CoreGraphics

/// A resolved swipe direction (SPEC §4.1 / §9). Eight directions: the four axes plus four
/// diagonals (for quarter snaps).
public enum Direction: String, Equatable, Sendable, CaseIterable {
    case left, right, up, down
    case upLeft, upRight, downLeft, downRight

    /// Resolve a swipe vector to a direction by dominant axis, with a diagonal band.
    ///
    /// The vector convention is math-standard: **+x is right, +y is up**. Callers translating
    /// `CGEvent` scroll deltas must normalize sign first (scroll-wheel deltas are inverted and
    /// device-dependent) — keeping that mapping out of the engine keeps `Direction` testable.
    ///
    /// `diagonalThreshold` is the ratio of the minor axis to the major axis at and above which
    /// the swipe counts as diagonal (default 0.4 ≈ within ~22° of 45°). Returns `nil` for a
    /// zero vector.
    public init?(scrollDelta v: CGVector, diagonalThreshold: Double = 0.4) {
        let ax = abs(v.dx)
        let ay = abs(v.dy)
        guard ax > 0 || ay > 0 else { return nil }

        let major = max(ax, ay)
        let minor = min(ax, ay)
        let isDiagonal = (minor / major) >= diagonalThreshold

        let towardRight = v.dx > 0
        let towardUp = v.dy > 0

        if isDiagonal {
            switch (towardUp, towardRight) {
            case (true, true):   self = .upRight
            case (true, false):  self = .upLeft
            case (false, true):  self = .downRight
            case (false, false): self = .downLeft
            }
        } else if ax >= ay {
            self = towardRight ? .right : .left
        } else {
            self = towardUp ? .up : .down
        }
    }
}
