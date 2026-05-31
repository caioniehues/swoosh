import CoreGraphics

/// The complete, **bounded** v1 configuration surface (SPEC §5). This is the whole knob set:
/// grid dimensions plus a tight option list — there is deliberately no config file or
/// layout-definition language (the declined config-DSL identity, STRATEGY §4.2). `validated()`
/// clamps every field to a sane range, which is what keeps "bounded" a checkable property rather
/// than a hope.
///
/// `Codable` via the standard library only (no Foundation) so the core stays headless-testable;
/// the `UserDefaults`-backed store lives in the app layer.
public struct SwooshSettings: Equatable, Sendable, Codable {
    /// Grid rows/cols for the hold-grid picker and the ⌃⌥1–9 numpad grid (SPEC §4.2 / §4.5).
    public var gridRows: Int
    public var gridCols: Int
    /// Ready/done haptics (SPEC §4.4); also off automatically without an actuator.
    public var hapticsEnabled: Bool
    /// Outer screen-edge margin, in points (SPEC §5 pixel gaps).
    public var outerGap: CGFloat
    /// Inter-window gutter, in points.
    public var innerGap: CGFloat
    /// Minimum swipe magnitude to commit (SPEC §4.1 recognizer).
    public var commitThreshold: Double
    /// Minor/major axis ratio at which a swipe counts as diagonal (SPEC §4.1).
    public var diagonalThreshold: Double

    public init(gridRows: Int = 3, gridCols: Int = 3, hapticsEnabled: Bool = true,
                outerGap: CGFloat = 0, innerGap: CGFloat = 0,
                commitThreshold: Double = 30, diagonalThreshold: Double = 0.4) {
        self.gridRows = gridRows
        self.gridCols = gridCols
        self.hapticsEnabled = hapticsEnabled
        self.outerGap = outerGap
        self.innerGap = innerGap
        self.commitThreshold = commitThreshold
        self.diagonalThreshold = diagonalThreshold
    }

    public static let `default` = SwooshSettings()

    /// Upper bound on grid dimensions — generous enough for ultrawide 5×1 / 6×1 layouts, bounded
    /// enough that the picker stays usable.
    public static let maxGridDimension = 12

    /// Clamp every field into its valid range. The settings UI should call this on every edit.
    public func validated() -> SwooshSettings {
        SwooshSettings(
            gridRows: min(max(gridRows, 1), Self.maxGridDimension),
            gridCols: min(max(gridCols, 1), Self.maxGridDimension),
            hapticsEnabled: hapticsEnabled,
            outerGap: max(0, outerGap),
            innerGap: max(0, innerGap),
            commitThreshold: max(1, commitThreshold),
            diagonalThreshold: min(max(diagonalThreshold, 0.05), 0.95)
        )
    }

    /// Outer-margin insets for the snap engine.
    public var outerInsets: PixelInsets { PixelInsets(outerGap) }
}
