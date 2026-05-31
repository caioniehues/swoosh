import CoreGraphics

/// The fraction-native snap engine (SPEC §5). Pure math: it resolves a `SnapTarget` to a
/// concrete `CGRect` in the same coordinate space as the `visibleFrame` it is given. It holds
/// no AX handles and touches no system APIs — the AppKit adapter and the actual `kAXPosition`
/// write live in `SwooshKit` (Layer 4), so this whole engine is exercised headlessly in CI.
public enum SnapEngine {

    /// Resolve a target to a `FractionalRect`. `.restore` has no fractional form (it pops the
    /// ring buffer) and returns `nil`; callers handle restore separately (SPEC §4.6).
    public static func fraction(for target: SnapTarget) -> FractionalRect? {
        switch target {
        case .fraction(let f):
            return f
        case .preset(let p):
            return p.fraction
        case .fullScreen:
            return .full
        case .gridCell(let row, let col, let rows, let cols):
            return gridFraction(row: row, col: col, rows: rows, cols: cols)
        case .restore:
            return nil
        }
    }

    /// Resolve a grid cell to a `FractionalRect`. Row 0 = top, col 0 = left. An ultrawide
    /// N-column layout is `gridCell(row: 0, col: i, rows: 1, cols: N)` — no special case.
    /// Out-of-range indices are clamped; non-positive dimensions fall back to the full frame.
    public static func gridFraction(row: Int, col: Int, rows: Int, cols: Int) -> FractionalRect {
        guard rows > 0, cols > 0 else { return .full }
        let r = min(max(row, 0), rows - 1)
        let c = min(max(col, 0), cols - 1)
        return FractionalRect(
            x: Double(c) / Double(cols),
            y: Double(r) / Double(rows),
            w: 1.0 / Double(cols),
            h: 1.0 / Double(rows)
        )
    }

    /// Resolve a `FractionalRect` against a concrete visible frame, then apply pixel insets.
    /// `visibleFrame` is in AX global top-left coordinates (the space we write to AX).
    public static func rect(for fraction: FractionalRect, in visibleFrame: CGRect) -> CGRect {
        let raw = CGRect(
            x: visibleFrame.minX + fraction.x * visibleFrame.width,
            y: visibleFrame.minY + fraction.y * visibleFrame.height,
            width: fraction.w * visibleFrame.width,
            height: fraction.h * visibleFrame.height
        )
        return apply(insets: fraction.inset, to: raw)
    }

    /// Resolve a target directly to a `CGRect`. Returns `nil` for `.restore` (no fractional form).
    public static func rect(for target: SnapTarget, in visibleFrame: CGRect) -> CGRect? {
        guard let f = fraction(for: target) else { return nil }
        return rect(for: f, in: visibleFrame)
    }

    /// Shrink `rect` by pixel insets. With a top-left origin, `top` pushes the top edge down,
    /// `left` pushes the left edge right; `bottom`/`right` pull the opposite edges in.
    static func apply(insets: PixelInsets, to rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX + insets.left,
            y: rect.minY + insets.top,
            width: rect.width - insets.left - insets.right,
            height: rect.height - insets.top - insets.bottom
        )
    }
}
