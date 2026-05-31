import CoreGraphics

/// A window frame tagged with an opaque id (e.g. a `CGWindowID`). The divider geometry works on
/// these values so it stays pure and testable — the live frames come from the geometry cache.
public struct WindowFrame: Equatable, Sendable {
    public let id: Int
    public let frame: CGRect
    public init(id: Int, frame: CGRect) {
        self.id = id
        self.frame = frame
    }
}

public enum DividerOrientation: Sendable, Equatable {
    case vertical    // separates a left window from a right window
    case horizontal  // separates a top window from a bottom window
}

/// A shared snapped edge between two windows that divider-drag can resize (SPEC §4.3).
public struct Divider: Equatable, Sendable {
    public let orientation: DividerOrientation
    /// The edge line: x for `.vertical`, y for `.horizontal` (AX global top-left coords).
    public let position: CGFloat
    /// Window id on the left (`.vertical`) or top (`.horizontal`).
    public let leading: Int
    /// Window id on the right (`.vertical`) or bottom (`.horizontal`).
    public let trailing: Int
    /// The overlapping extent along the edge (y-range for vertical, x-range for horizontal).
    public let spanMin: CGFloat
    public let spanMax: CGFloat

    public init(orientation: DividerOrientation, position: CGFloat,
                leading: Int, trailing: Int, spanMin: CGFloat, spanMax: CGFloat) {
        self.orientation = orientation
        self.position = position
        self.leading = leading
        self.trailing = trailing
        self.spanMin = spanMin
        self.spanMax = spanMax
    }
}

/// Detects the shared snapped edge under the cursor (SPEC §4.3). The relationship is inferred
/// from current frames, not stored state, so it survives windows being moved by other tools.
/// Pure: this runs synchronously on the mouse-down event using fast geometry, never AX.
public enum DividerLocator {
    /// The divider under `cursor`, or `nil` if the cursor is not in the narrow band straddling
    /// two windows' shared edge. `edgeTolerance` is how close two edges must be to count as
    /// shared; `bandHalfWidth` is the grab band; `minOverlap` rejects edges that barely touch.
    public static func divider(at cursor: CGPoint, among windows: [WindowFrame],
                               edgeTolerance: CGFloat = 6, bandHalfWidth: CGFloat = 8,
                               minOverlap: CGFloat = 40) -> Divider? {
        for i in windows.indices {
            for j in windows.indices where j != i {
                let a = windows[i].frame, b = windows[j].frame

                // Vertical edge: window `a` sits left of `b`, sharing a.maxX ≈ b.minX.
                if abs(a.maxX - b.minX) <= edgeTolerance {
                    let lo = max(a.minY, b.minY), hi = min(a.maxY, b.maxY)
                    let edge = (a.maxX + b.minX) / 2
                    if hi - lo >= minOverlap, abs(cursor.x - edge) <= bandHalfWidth,
                       cursor.y >= lo, cursor.y <= hi {
                        return Divider(orientation: .vertical, position: edge,
                                       leading: windows[i].id, trailing: windows[j].id,
                                       spanMin: lo, spanMax: hi)
                    }
                }

                // Horizontal edge: window `a` sits above `b`, sharing a.maxY ≈ b.minY.
                if abs(a.maxY - b.minY) <= edgeTolerance {
                    let lo = max(a.minX, b.minX), hi = min(a.maxX, b.maxX)
                    let edge = (a.maxY + b.minY) / 2
                    if hi - lo >= minOverlap, abs(cursor.y - edge) <= bandHalfWidth,
                       cursor.x >= lo, cursor.x <= hi {
                        return Divider(orientation: .horizontal, position: edge,
                                       leading: windows[i].id, trailing: windows[j].id,
                                       spanMin: lo, spanMax: hi)
                    }
                }
            }
        }
        return nil
    }
}

/// Computes the paired window frames when a divider is dragged to a new position (SPEC §4.3).
/// `minSize` clamps the drag so neither window collapses. Pure — the AX write happens off-thread.
public enum DividerResolver {
    public static func resize(leading: CGRect, trailing: CGRect, orientation: DividerOrientation,
                              to position: CGFloat, minSize: CGFloat = 100)
        -> (leading: CGRect, trailing: CGRect) {
        switch orientation {
        case .vertical:
            let clamped = min(max(position, leading.minX + minSize), trailing.maxX - minSize)
            let newLeading = CGRect(x: leading.minX, y: leading.minY,
                                    width: clamped - leading.minX, height: leading.height)
            let newTrailing = CGRect(x: clamped, y: trailing.minY,
                                     width: trailing.maxX - clamped, height: trailing.height)
            return (newLeading, newTrailing)
        case .horizontal:
            let clamped = min(max(position, leading.minY + minSize), trailing.maxY - minSize)
            let newLeading = CGRect(x: leading.minX, y: leading.minY,
                                    width: leading.width, height: clamped - leading.minY)
            let newTrailing = CGRect(x: trailing.minX, y: clamped,
                                     width: trailing.width, height: trailing.maxY - clamped)
            return (newLeading, newTrailing)
        }
    }
}
