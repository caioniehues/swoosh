import CoreGraphics

/// A window's current snap state, used by the stateful swipe toggles (SPEC §4.1):
/// ↑ on an already-top-half window → fullscreen; ↓ on an already-snapped window → restore.
public enum SnapState: Equatable, Sendable {
    case unsnapped
    case preset(Preset)
}

/// Classifies a window frame against the preset layouts — the inverse of `SnapEngine.rect`.
/// Pure: it takes the window frame and the screen's visible frame (both AX top-left coords) and
/// returns which preset, if any, the window currently occupies. The AX read that produces the
/// frame happens off-thread in `SnapApplier`; the comparison itself is testable in isolation.
public enum SnapClassifier {
    /// The first preset whose resolved rect matches `frame` within `tolerance` points, else `.unsnapped`.
    public static func classify(frame: CGRect, in visibleFrame: CGRect, tolerance: CGFloat = 2) -> SnapState {
        for preset in Preset.allCases {
            let candidate = SnapEngine.rect(for: preset.fraction, in: visibleFrame)
            if approxEqual(frame, candidate, tolerance: tolerance) {
                return .preset(preset)
            }
        }
        return .unsnapped
    }

    static func approxEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat) -> Bool {
        abs(a.minX - b.minX) <= tolerance &&
        abs(a.minY - b.minY) <= tolerance &&
        abs(a.width - b.width) <= tolerance &&
        abs(a.height - b.height) <= tolerance
    }
}
