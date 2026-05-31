import CoreGraphics

/// The hold-grid picker geometry (SPEC §4.2). While two fingers are held on the titlebar, the
/// cell under the cursor is the destination; releasing commits, and moving the cursor off the
/// screen cancels. The grid is configurable (3×3 default, or 5×1 ultrawide, etc.) — because the
/// engine is fraction-native, any cell is just a `gridCell` target.
///
/// Pure geometry: hold-duration detection is a live-timer concern (SwooshKit); resolving which
/// cell a cursor is in, and whether the cursor has left the grid (cancel), is testable here.
public enum HoldGrid {
    /// The grid cell under `cursor`, or `nil` if the cursor is outside the visible frame (cancel).
    public static func cell(at cursor: CGPoint, rows: Int, cols: Int, in visibleFrame: CGRect) -> SnapTarget? {
        guard rows > 0, cols > 0, visibleFrame.contains(cursor) else { return nil }
        let fx = (cursor.x - visibleFrame.minX) / visibleFrame.width
        let fy = (cursor.y - visibleFrame.minY) / visibleFrame.height
        let col = min(cols - 1, max(0, Int(fx * CGFloat(cols))))
        let row = min(rows - 1, max(0, Int(fy * CGFloat(rows))))
        return .gridCell(row: row, col: col, rows: rows, cols: cols)
    }
}
