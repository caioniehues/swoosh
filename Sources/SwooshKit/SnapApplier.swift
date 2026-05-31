import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import SwooshCore

/// Layer 4 act (SPEC §6, ported from the M0 spike's S3 probe). Runs entirely on the
/// `swoosh.ax` serial queue — **never** the tap thread (that is the FB11586064 ~500 ms stall).
/// Resolves the window under the cursor via AX, computes the destination rect with the pure
/// `SnapEngine`, and writes it with the Rectangle-derived size→position→size sequence (KTD7).
public final class SnapApplier {
    private let queue = DispatchQueue(label: "swoosh.ax", qos: .userInteractive)

    /// Per-app frame history for restore (SPEC §4.6). Keyed by pid as an M2 approximation; a
    /// precise per-window key needs a stable window id (deferred — avoid adding a private AX SPI).
    /// Accessed only on `queue`, so serialized without a lock.
    private var histories: [pid_t: FrameHistory] = [:]

    public init() {}

    // MARK: - Public enqueue API (fire-and-forget from the tap thread)

    /// Apply an explicit target to the window under `location` (e.g. hold-grid, keyboard).
    public func enqueueApply(_ target: SnapTarget, at location: CGPoint) {
        queue.async { [weak self] in _ = self?.apply(target, at: location) }
    }

    /// Apply a committed swipe: locate the window, classify its current snap state, resolve the
    /// target with the stateful toggles, and write it (SPEC §4.1).
    public func enqueueSwipe(_ direction: Direction, at location: CGPoint) {
        queue.async { [weak self] in self?.applySwipe(direction, at: location) }
    }

    /// Resize two snapped windows in lockstep as their shared divider is dragged (SPEC §4.3).
    /// `leading`/`trailing` are the windows' frames at drag start; `position` is the new divider
    /// coordinate (x for vertical, y for horizontal). Runs on `swoosh.ax`.
    public func enqueueDividerResize(leading: CGRect, trailing: CGRect,
                                     orientation: DividerOrientation, to position: CGFloat) {
        queue.async { [weak self] in
            guard let self else { return }
            let (newLeading, newTrailing) = DividerResolver.resize(
                leading: leading, trailing: trailing, orientation: orientation, to: position)
            // Re-locate each window by hit-testing a point inside its start frame, then write both.
            if let l = self.locate(at: CGPoint(x: leading.midX, y: leading.midY)) {
                _ = self.write(newLeading, to: l)
            }
            if let t = self.locate(at: CGPoint(x: trailing.midX, y: trailing.midY)) {
                _ = self.write(newTrailing, to: t)
            }
        }
    }

    /// Keyboard actions target the FOCUSED window (SPEC §4.5), not the cursor.
    public func enqueueApplyFocused(_ target: SnapTarget) {
        queue.async { [weak self] in
            guard let self, let located = self.locateFocused() else { return }
            self.applyResolved(target, to: located)
        }
    }

    public func enqueueSwipeFocused(_ direction: Direction) {
        queue.async { [weak self] in
            guard let self, let located = self.locateFocused() else { return }
            let state = SnapClassifier.classify(frame: located.frame, in: located.visibleFrame)
            self.applyResolved(SwipeResolver.target(for: direction, currentState: state), to: located)
        }
    }

    /// Exit native fullscreen on the focused window (SPEC §4.6).
    public func enqueueExitFullscreenFocused() {
        queue.async { [weak self] in
            guard let self, let located = self.locateFocused() else { return }
            self.exitFullscreen(located)
        }
    }

    // MARK: - Apply implementations (run on `queue`)

    /// Resolve and write a target to an already-located window (shared by cursor + focused paths).
    private func applyResolved(_ target: SnapTarget, to located: Located) {
        if case .restore = target { _ = restore(located); return }
        guard let rect = SnapEngine.rect(for: target, in: located.visibleFrame) else { return }
        pushHistory(located)
        _ = write(rect, to: located)
    }

    /// Exit fullscreen via the **private** `"AXFullScreen"` attribute (SPEC §4.6, capability
    /// ledger STRATEGY §5); fall back to pressing the fullscreen button. AX writes are confined
    /// to this Layer-4 file.
    private func exitFullscreen(_ located: Located) {
        if readBool(located.window, "AXFullScreen") == true {
            AXUIElementSetAttributeValue(located.window, "AXFullScreen" as CFString, kCFBooleanFalse)
            return
        }
        var button: CFTypeRef?
        if AXUIElementCopyAttributeValue(located.window, "AXFullScreenButton" as CFString, &button) == .success,
           let b = button, CFGetTypeID(b) == AXUIElementGetTypeID() {
            AXUIElementPerformAction((b as! AXUIElement), kAXPressAction as CFString)
        }
    }

    @discardableResult
    public func apply(_ target: SnapTarget, at location: CGPoint) -> Bool {
        guard let located = locate(at: location) else { return false }
        if case .restore = target { return restore(located) }
        guard let rect = SnapEngine.rect(for: target, in: located.visibleFrame) else { return false }
        pushHistory(located)
        return write(rect, to: located)
    }

    private func applySwipe(_ direction: Direction, at location: CGPoint) {
        guard let located = locate(at: location) else { return }
        let state = SnapClassifier.classify(frame: located.frame, in: located.visibleFrame)
        let target = SwipeResolver.target(for: direction, currentState: state)
        if case .restore = target { _ = restore(located); return }
        guard let rect = SnapEngine.rect(for: target, in: located.visibleFrame) else { return }
        pushHistory(located)
        _ = write(rect, to: located)
    }

    private func pushHistory(_ located: Located) {
        var hist = histories[located.pid] ?? FrameHistory()
        hist.push(located.frame)
        histories[located.pid] = hist
    }

    private func restore(_ located: Located) -> Bool {
        guard var hist = histories[located.pid], let previous = hist.popPrevious() else { return false }
        histories[located.pid] = hist
        return write(previous, to: located)
    }

    // MARK: - Locate (AX)

    private struct Located {
        let window: AXUIElement
        let app: AXUIElement?
        let pid: pid_t
        let frame: CGRect          // current window frame, AX global top-left
        let visibleFrame: CGRect   // containing screen's visible frame, AX global top-left
    }

    /// Build a `Located` from a resolved window element (current frame + containing screen).
    private func located(from window: AXUIElement, requireStandard: Bool = true) -> Located? {
        AXUIElementSetMessagingTimeout(window, 0.15)
        if requireStandard, readString(window, kAXSubroleAttribute) != (kAXStandardWindowSubrole as String) {
            return nil
        }
        guard let pos = readPoint(window, kAXPositionAttribute),
              let size = readSize(window, kAXSizeAttribute) else { return nil }
        let frame = CGRect(origin: pos, size: size)
        guard let visibleFrame = visibleFrameAX(containing: CGPoint(x: frame.midX, y: frame.midY)) else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        return Located(window: window, app: appElement(of: window), pid: pid,
                       frame: frame, visibleFrame: visibleFrame)
    }

    /// The standard window under `location` (cursor-driven gestures).
    private func locate(at location: CGPoint) -> Located? {
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(location.x), Float(location.y), &element) == .success,
              let el = element, let window = enclosingWindow(el) else { return nil }
        return located(from: window)
    }

    /// The system-wide focused window (keyboard-driven actions act here, not under the cursor).
    private func locateFocused() -> Located? {
        let systemWide = AXUIElementCreateSystemWide()
        var appRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &appRef) == .success,
              let app = appRef, CFGetTypeID(app) == AXUIElementGetTypeID() else { return nil }
        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue((app as! AXUIElement), kAXFocusedWindowAttribute as CFString, &winRef) == .success,
              let win = winRef, CFGetTypeID(win) == AXUIElementGetTypeID() else { return nil }
        return located(from: (win as! AXUIElement), requireStandard: false)
    }

    /// The Rectangle-derived write: clear AXEnhancedUserInterface, size→position→size, read-back,
    /// restore the attribute. Returns whether the write landed (read-back verified).
    @discardableResult
    private func write(_ rect: CGRect, to located: Located) -> Bool {
        let priorEUI = located.app.flatMap { readBool($0, "AXEnhancedUserInterface") }
        if let app = located.app, priorEUI == true {
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
        }
        // macOS clamps window size to the current display before honoring a cross-display move,
        // so the leading size write is load-bearing.
        setSize(located.window, rect.size)
        setPoint(located.window, rect.origin)
        setSize(located.window, rect.size)
        let landed = readPoint(located.window, kAXPositionAttribute).map {
            abs($0.x - rect.minX) < 3 && abs($0.y - rect.minY) < 3
        } ?? false
        if let app = located.app, priorEUI == true {
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
        return landed
    }

    // MARK: - Screen → AX coordinate resolution

    /// The visible frame (menu-bar/Dock-excluded) of the screen containing `pointAX`, in AX
    /// global top-left coords. The flip uses the **primary** display's height (SPEC §5/§10).
    private func visibleFrameAX(containing pointAX: CGPoint) -> CGRect? {
        let primaryH = SnapApplier.primaryHeight()
        for screen in NSScreen.screens {
            if Coordinates.flip(screen.frame, primaryHeight: primaryH).contains(pointAX) {
                return Coordinates.flip(screen.visibleFrame, primaryHeight: primaryH)
            }
        }
        if let main = NSScreen.main {
            return Coordinates.flip(main.visibleFrame, primaryHeight: primaryH)
        }
        return nil
    }

    private static func primaryHeight() -> CGFloat {
        (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main)?.frame.height ?? 0
    }

    // MARK: - AX helpers (ported from the M0 AXActProbe)

    private func enclosingWindow(_ element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &value) == .success,
           let v = value, CFGetTypeID(v) == AXUIElementGetTypeID() {
            return (v as! AXUIElement)
        }
        var current: AXUIElement? = element
        for _ in 0 ..< 12 {
            guard let c = current else { break }
            if readString(c, kAXRoleAttribute) == (kAXWindowRole as String) { return c }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(c, kAXParentAttribute as CFString, &parent) == .success,
                  let p = parent, CFGetTypeID(p) == AXUIElementGetTypeID() else { break }
            current = (p as! AXUIElement)
        }
        return nil
    }

    private func appElement(of window: AXUIElement) -> AXUIElement? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return nil }
        return AXUIElementCreateApplication(pid)
    }

    private func readString(_ el: AXUIElement, _ attr: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func readBool(_ el: AXUIElement, _ attr: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success,
              let v = value, CFGetTypeID(v) == CFBooleanGetTypeID() else { return nil }
        return CFBooleanGetValue((v as! CFBoolean))
    }

    private func readPoint(_ el: AXUIElement, _ attr: String) -> CGPoint? {
        guard let v = axValue(el, attr) else { return nil }
        var out = CGPoint.zero
        return AXValueGetValue(v, .cgPoint, &out) ? out : nil
    }

    private func readSize(_ el: AXUIElement, _ attr: String) -> CGSize? {
        guard let v = axValue(el, attr) else { return nil }
        var out = CGSize.zero
        return AXValueGetValue(v, .cgSize, &out) ? out : nil
    }

    private func axValue(_ el: AXUIElement, _ attr: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success,
              let v = value, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        return (v as! AXValue)
    }

    private func setPoint(_ el: AXUIElement, _ p: CGPoint) {
        var p = p
        if let v = AXValueCreate(.cgPoint, &p) {
            AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, v)
        }
    }

    private func setSize(_ el: AXUIElement, _ s: CGSize) {
        var s = s
        if let v = AXValueCreate(.cgSize, &s) {
            AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, v)
        }
    }
}
