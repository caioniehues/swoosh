import Foundation
import ApplicationServices
import CoreGraphics

/// U4 — S3: off-thread AX locate + window move/resize.
///
/// Everything here runs on a single `swoosh.ax` serial queue — NEVER on the tap
/// thread (the FB11586064 ~500ms stall). The act path mirrors Rectangle (KTD7):
/// a tight messaging timeout, clear `AXEnhancedUserInterface` on the app element
/// before writing (it silently corrupts position writes in Chrome/Electron),
/// the size → position → size sequence (macOS clamps to the current display
/// before a cross-display move), and a read-back to catch silent no-ops.
///
/// AX requires Accessibility; build-validated here, run with `M0_AX=1` on
/// hardware. The self-test nudges the window under the cursor 20pt and restores.
final class AXActProbe {
    private let queue = DispatchQueue(label: "swoosh.ax", qos: .userInteractive)
    private let log: DecisionLog

    init(log: DecisionLog) { self.log = log }

    /// Dispatched from the tap (never awaited). Here, run synchronously for the
    /// self-test so the process can report and exit.
    func runSelfTest() { queue.sync { self.act() } }

    private func act() {
        let systemWide = AXUIElementCreateSystemWide()
        let cursor = CGEvent(source: nil)?.location ?? CGPoint(x: 300, y: 200)

        var element: AXUIElement?
        let hit = AXUIElementCopyElementAtPosition(systemWide, Float(cursor.x), Float(cursor.y), &element)
        guard hit == .success, let el = element else {
            log.record("ax.hitTest", ["ok": false, "axError": Int(hit.rawValue), "note": note(for: hit)])
            return
        }

        guard let window = enclosingWindow(el) else {
            log.record("ax.window", ["ok": false, "reason": "no kAXWindow ancestor under cursor"])
            return
        }
        AXUIElementSetMessagingTimeout(window, 0.15)
        let role = string(window, kAXRoleAttribute)
        let subrole = string(window, kAXSubroleAttribute)
        log.record("ax.window", ["ok": true, "role": role ?? "?", "subrole": subrole ?? "?"])

        guard let pos0 = point(window, kAXPositionAttribute),
              let size0 = size(window, kAXSizeAttribute) else {
            log.record("ax.read", ["ok": false]); return
        }

        // Clear AXEnhancedUserInterface on the app element (restored after).
        let app = appElement(of: window)
        let priorEUI = app.flatMap { boolean($0, "AXEnhancedUserInterface") }
        if let app, priorEUI == true {
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
        }

        // size → position → size (KTD7). Nudge 20pt; same size.
        let target = CGPoint(x: pos0.x + 20, y: pos0.y + 20)
        setSize(window, size0)
        setPoint(window, target)
        setSize(window, size0)

        let landedPos = point(window, kAXPositionAttribute) ?? .zero
        let landed = abs(landedPos.x - target.x) < 3 && abs(landedPos.y - target.y) < 3
        log.record("ax.write", [
            "from": ["x": pos0.x, "y": pos0.y],
            "target": ["x": target.x, "y": target.y],
            "readback": ["x": landedPos.x, "y": landedPos.y],
            "landed": landed,
            "note": landed ? "write landed" : "silent no-op (app may ignore kAXPosition) — logged, not crashed",
        ])

        // Restore original frame + EUI.
        setPoint(window, pos0); setSize(window, size0)
        if let app, priorEUI == true {
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
    }

    // MARK: - AX helpers

    private func enclosingWindow(_ element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &value) == .success,
           let v = value, CFGetTypeID(v) == AXUIElementGetTypeID() {
            return (v as! AXUIElement)
        }
        var current: AXUIElement? = element
        for _ in 0..<12 {
            guard let c = current else { break }
            if string(c, kAXRoleAttribute) == (kAXWindowRole as String) { return c }
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

    private func string(_ el: AXUIElement, _ attr: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func boolean(_ el: AXUIElement, _ attr: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success,
              let v = value, CFGetTypeID(v) == CFBooleanGetTypeID() else { return nil }
        return CFBooleanGetValue((v as! CFBoolean))
    }

    private func point(_ el: AXUIElement, _ attr: String) -> CGPoint? {
        guard let v = axValue(el, attr) else { return nil }
        var out = CGPoint.zero
        return AXValueGetValue(v, .cgPoint, &out) ? out : nil
    }

    private func size(_ el: AXUIElement, _ attr: String) -> CGSize? {
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

    private func note(for error: AXError) -> String {
        switch error {
        case .apiDisabled: return "Accessibility not granted (apiDisabled)"
        case .notImplemented: return "target app has no AX tree (Qt/OpenGL/etc.)"
        case .cannotComplete: return "app unresponsive / timed out / stale handle"
        default: return "see AXError \(error.rawValue)"
        }
    }
}
