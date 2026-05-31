import CoreGraphics

/// Pixel gaps applied after fraction resolution: outer margins / inter-window gutters.
///
/// SPEC §5's sketch used `NSEdgeInsets`, but that lives in AppKit and would pull a UI
/// framework into the pure engine. A local value type keeps `SwooshCore` headless-testable;
/// the field semantics (top/left/bottom/right in points) are identical.
public struct PixelInsets: Equatable, Sendable, Codable {
    public var top: CGFloat
    public var left: CGFloat
    public var bottom: CGFloat
    public var right: CGFloat

    public init(top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    /// Uniform inset on all four sides.
    public init(_ all: CGFloat) {
        self.init(top: all, left: all, bottom: all, right: all)
    }

    public static let zero = PixelInsets()
}

/// A rectangle expressed as fractions (0…1) of a screen's `visibleFrame`, with optional
/// pixel insets. (0,0) is top-left. This is **the engine's native vocabulary** (SPEC §5):
/// presets and grids are conveniences that resolve to one of these. Keeping fractions native
/// is what kills Swish's 3×3 size ceiling — an N-column ultrawide layout is just arithmetic,
/// not a new code path.
///
/// Resolution (`SnapEngine.rect(for:in:)`) happens against the `visibleFrame` of the screen
/// containing the window, expressed in AX global coordinates (top-left origin, +y down). No
/// flip is needed at the AX apply boundary; see `Coordinates.flip` for the one case that does.
public struct FractionalRect: Equatable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double
    public var inset: PixelInsets

    public init(x: Double, y: Double, w: Double, h: Double, inset: PixelInsets = .zero) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.inset = inset
    }

    /// The whole visible frame.
    public static let full = FractionalRect(x: 0, y: 0, w: 1, h: 1)
}
