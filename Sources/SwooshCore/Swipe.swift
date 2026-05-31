import CoreGraphics

/// Maps a committed swipe direction to a `SnapTarget` (SPEC §4.1), including the two stateful
/// toggles. Pure — the window's current state is passed in, not read here.
public enum SwipeResolver {
    public static func target(for direction: Direction, currentState: SnapState) -> SnapTarget {
        switch direction {
        case .left:      return .preset(.leftHalf)
        case .right:     return .preset(.rightHalf)
        case .up:
            // Top half — or full-screen if already on the top half.
            return currentState == .preset(.topHalf) ? .fullScreen : .preset(.topHalf)
        case .down:
            // Bottom half — or restore the previous frame if already snapped.
            if case .unsnapped = currentState { return .preset(.bottomHalf) }
            return .restore
        case .upLeft:    return .preset(.topLeftQuarter)
        case .upRight:   return .preset(.topRightQuarter)
        case .downLeft:  return .preset(.bottomLeftQuarter)
        case .downRight: return .preset(.bottomRightQuarter)
        }
    }
}

/// Accumulates scroll deltas over a single two-finger gesture and resolves the committed
/// direction. The live tap drives this on its (single) thread; it is a value type so it is
/// trivially testable. The commit threshold keeps tiny jitters from triggering a snap.
public struct SwipeGesture: Equatable, Sendable {
    public private(set) var accumulated = CGVector(dx: 0, dy: 0)
    public private(set) var isActive = false
    public let commitThreshold: Double

    public init(commitThreshold: Double = 30) {
        self.commitThreshold = commitThreshold
    }

    /// Feed one scroll sample. `began` (re)starts the gesture; `changed` accumulates; any other
    /// phase (ended/cancelled/none) leaves the accumulation for the caller to read then `reset`.
    ///
    /// `delta` uses the engine convention: +x right, +y up (callers normalize CG scroll signs).
    public mutating func add(phase: ScrollPhase, delta: CGVector) {
        switch phase {
        case .began:
            accumulated = delta
            isActive = true
        case .changed where isActive:
            accumulated = CGVector(dx: accumulated.dx + delta.dx, dy: accumulated.dy + delta.dy)
        default:
            break
        }
    }

    public var magnitude: Double {
        let dx = Double(accumulated.dx), dy = Double(accumulated.dy)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// The committed direction if the gesture crossed the threshold, else `nil` (too small / jitter).
    public func committedDirection(diagonalThreshold: Double = 0.4) -> Direction? {
        guard magnitude >= commitThreshold else { return nil }
        return Direction(scrollDelta: accumulated, diagonalThreshold: diagonalThreshold)
    }

    public mutating func reset() {
        accumulated = CGVector(dx: 0, dy: 0)
        isActive = false
    }
}
