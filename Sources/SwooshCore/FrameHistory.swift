import CoreGraphics

/// A per-window bounded frame history (SPEC §4.6). `Swipe ↓` on a snapped window, the keyboard
/// restore (`⌃⌥⏎`), and the post-snap restore all pop the most recent frame, so repeated
/// restore walks back through recent placements. Default depth 4 — the original pre-snap frame
/// is the deepest entry until evicted by the ring's bound.
public struct FrameHistory: Equatable, Sendable {
    public let capacity: Int
    private var frames: [CGRect] = []

    public init(capacity: Int = 4) {
        precondition(capacity > 0, "FrameHistory capacity must be positive")
        self.capacity = capacity
    }

    /// Number of frames currently retained.
    public var count: Int { frames.count }

    public var isEmpty: Bool { frames.isEmpty }

    /// Record the current frame (before a snap). Evicts the oldest entry past `capacity`.
    public mutating func push(_ frame: CGRect) {
        frames.append(frame)
        if frames.count > capacity {
            frames.removeFirst(frames.count - capacity)
        }
    }

    /// Pop and return the most-recently pushed frame, or `nil` if the history is empty.
    public mutating func popPrevious() -> CGRect? {
        frames.popLast()
    }

    /// The most-recent frame without removing it.
    public func peek() -> CGRect? {
        frames.last
    }
}
