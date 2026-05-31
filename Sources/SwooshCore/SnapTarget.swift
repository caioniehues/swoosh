import CoreGraphics

/// A named convenience layout. Every preset compiles to a `FractionalRect` — presets are
/// sugar, not a parallel vocabulary (SPEC §5). v1 ships a tight default set: halves, quarters,
/// thirds, two-thirds, center, and maximize.
public enum Preset: String, CaseIterable, Sendable, Codable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeftQuarter, topRightQuarter, bottomLeftQuarter, bottomRightQuarter
    case leftThird, centerThird, rightThird
    case leftTwoThirds, rightTwoThirds
    case center            // centered at 2/3 × 2/3
    case maximize          // the full visible frame

    /// The fractional rectangle this preset resolves to. Top-left origin: y grows downward.
    public var fraction: FractionalRect {
        switch self {
        case .leftHalf:           return FractionalRect(x: 0,       y: 0,   w: 0.5,     h: 1)
        case .rightHalf:          return FractionalRect(x: 0.5,     y: 0,   w: 0.5,     h: 1)
        case .topHalf:            return FractionalRect(x: 0,       y: 0,   w: 1,       h: 0.5)
        case .bottomHalf:         return FractionalRect(x: 0,       y: 0.5, w: 1,       h: 0.5)
        case .topLeftQuarter:     return FractionalRect(x: 0,       y: 0,   w: 0.5,     h: 0.5)
        case .topRightQuarter:    return FractionalRect(x: 0.5,     y: 0,   w: 0.5,     h: 0.5)
        case .bottomLeftQuarter:  return FractionalRect(x: 0,       y: 0.5, w: 0.5,     h: 0.5)
        case .bottomRightQuarter: return FractionalRect(x: 0.5,     y: 0.5, w: 0.5,     h: 0.5)
        case .leftThird:          return FractionalRect(x: 0,       y: 0,   w: 1.0 / 3, h: 1)
        case .centerThird:        return FractionalRect(x: 1.0 / 3, y: 0,   w: 1.0 / 3, h: 1)
        case .rightThird:         return FractionalRect(x: 2.0 / 3, y: 0,   w: 1.0 / 3, h: 1)
        case .leftTwoThirds:      return FractionalRect(x: 0,       y: 0,   w: 2.0 / 3, h: 1)
        case .rightTwoThirds:     return FractionalRect(x: 1.0 / 3, y: 0,   w: 2.0 / 3, h: 1)
        case .center:             return FractionalRect(x: 1.0 / 6, y: 1.0 / 6, w: 2.0 / 3, h: 2.0 / 3)
        case .maximize:           return .full
        }
    }
}

/// The core snap abstraction (SPEC §5). A tagged union whose **load-bearing case is
/// `.fraction`** — the others are conveniences that resolve to a `FractionalRect`. Per
/// CLAUDE.md this must never collapse into a closed set of named-position cases; that is the
/// architectural decision that removes the 3×3 ceiling.
public enum SnapTarget: Equatable, Sendable {
    /// The native vocabulary: an arbitrary fractional rectangle.
    case fraction(FractionalRect)
    /// A named preset (resolves to `.fraction`).
    case preset(Preset)
    /// Any N×M grid cell, including ultrawide 5×1 (resolves to `.fraction`). Row 0 = top, col 0 = left.
    case gridCell(row: Int, col: Int, rows: Int, cols: Int)
    /// The whole visible frame.
    case fullScreen
    /// Pop the per-window frame ring buffer (SPEC §4.6); resolved by the caller, not the engine.
    case restore
}
