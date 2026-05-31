import CoreGraphics

/// A screen edge. Used by divider-drag (SPEC §4.3) to describe the shared edge between two
/// snapped windows, and elsewhere to name sides.
public enum Edge: String, Sendable, Codable, CaseIterable {
    case top, bottom, left, right
}

/// Coordinate-space conversion helpers (SPEC §5 / §10).
///
/// AX window geometry is **global, top-left origin, +y down, referenced to the primary
/// display** — so a resolved `FractionalRect` is written via `kAXPosition` with **no flip**.
/// A flip is required **only** when an intermediate computation uses AppKit/`NSScreen`
/// (bottom-left origin) coordinates, and that flip must use the **primary** screen's height
/// as the Y reference — using the window's own screen height is wrong on a secondary display
/// of a different height.
public enum Coordinates {
    /// Convert `rect` between AppKit bottom-left space and AX top-left global space.
    ///
    /// The transform is its own inverse, so the same call maps either direction. `primaryHeight`
    /// must be the **primary** display's height in points.
    public static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
