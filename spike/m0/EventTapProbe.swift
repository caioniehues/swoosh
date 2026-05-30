import Foundation
import CoreGraphics
import ApplicationServices   // AXIsProcessTrusted()
import Darwin

/// U3 — S1: session `CGEventTap` capture & suppression with a never-block proof.
///
/// The suppress/pass decision is made SYNCHRONOUSLY in the tap callback from
/// three in-thread signals — the finger-count atomic (U2), the scroll phase, and
/// a fast `CGWindowList` titlebar-band check — and NEVER touches AX (an AX call
/// here is the ~500ms FB11586064 stall; the precise hit-test is U4's off-thread
/// job). A swallowed event cannot be un-swallowed, so an uncertain state passes.
///
/// The active tap requires Accessibility; build-validated here, run with
/// `M0_TAP=1` on hardware. `M0_DWELL_MS=<n>` engages the dwell-sweep that
/// MEASURES the per-OS `kCGEventTapDisabledByTimeout` ceiling.
final class EventTapProbe {
    private let fingerCount: UnsafePointer<Int32>
    private let log: DecisionLog
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    // Never-block instrumentation.
    private var maxCallbackNanos: UInt64 = 0
    private var callbackCount: UInt64 = 0
    private var suppressedCount: UInt64 = 0
    private var sawMayBegin = false
    private var firstPhases: [Int] = []

    /// Dwell-sweep: deliberately burn this many ms in the callback to provoke
    /// `kCGEventTapDisabledByTimeout` and measure the real ceiling (not folklore).
    var dwellMillis: Double = 0

    init(fingerCount: UnsafePointer<Int32>, log: DecisionLog) {
        self.fingerCount = fingerCount
        self.log = log
    }

    func install() -> Bool {
        let mask = CGEventMask(1) << UInt64(CGEventType.scrollWheel.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,            // session level — no root required
            place: .headInsertEventTap,         // first in the chain
            options: .defaultTap,               // active filter — can swallow
            eventsOfInterest: mask,             // scroll-wheel only (don't clobber 3-finger lookup)
            callback: EventTapProbe.callback,
            userInfo: refcon
        ) else {
            log.record("tap.create", [
                "ok": false,
                "axTrusted": AXIsProcessTrusted(),
                "reason": "tapCreate returned nil — Accessibility not granted, or the "
                        + "Sequoia LSBackgroundOnly→NULL regression (we run as a bare binary to dodge it)",
            ])
            return false
        }
        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = src
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        log.record("tap.create", ["ok": true, "axTrusted": AXIsProcessTrusted()])
        return true
    }

    // @convention(c) trampoline — recovers `self` from the refcon.
    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let probe = Unmanaged<EventTapProbe>.fromOpaque(refcon).takeUnretainedValue()
        return probe.handle(type: type, event: event)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables the tap on a slow callback or secure input —
        // re-arm immediately (the canonical Hammerspoon pattern).
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            log.record("tap.reenabled",
                       ["reason": type == .tapDisabledByTimeout ? "timeout" : "userInput"])
            return nil
        }

        let start = DispatchTime.now().uptimeNanoseconds
        if dwellMillis > 0 { Thread.sleep(forTimeInterval: dwellMillis / 1000.0) }

        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)
        let phase = Int(event.getIntegerValueField(.scrollWheelEventScrollPhase))
        if phase == 128 { sawMayBegin = true }            // kCGScrollPhaseMayBegin (FB9724671)
        if firstPhases.count < 16 { firstPhases.append(phase) }

        var suppress = false
        if isContinuous == 1 {                            // trackpad, not a discrete mouse wheel
            let fingers = m0_atomic_load_relaxed(fingerCount)
            // All three conditions, all checkable in-thread (SPEC §6.2).
            if fingers == 2 && (phase == 1 || phase == 2) && cursorOverTitlebar(event.location) {
                suppress = true
            }
        }

        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        if elapsed > maxCallbackNanos { maxCallbackNanos = elapsed }
        callbackCount += 1
        if suppress { suppressedCount += 1 }

        return suppress ? nil : Unmanaged.passUnretained(event)
    }

    /// Fast in-thread titlebar-band check via `CGWindowList` — NO AX (that would
    /// stall the tap). Spike-grade: frontmost on-screen layer-0 window's top band.
    /// (The off-thread-cache vs in-thread fork and stale-geometry failure modes
    /// are the plan's Open Questions; this is the in-thread arm.)
    private func cursorOverTitlebar(_ cursor: CGPoint) -> Bool {
        guard let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return false }
        for window in info {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = window[kCGWindowBounds as String],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as! CFDictionary)
            else { continue }
            let titlebarHeight: CGFloat = 28      // default; custom titlebars derived later
            let band = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: titlebarHeight)
            return band.contains(cursor)          // frontmost on-screen window only
        }
        return false
    }

    func report() {
        log.record("tap.summary", [
            "callbacks": Int(callbackCount),
            "suppressed": Int(suppressedCount),
            "maxCallbackMicros": Double(maxCallbackNanos) / 1000.0,
            "dwellMillis": dwellMillis,
            "sawMayBegin_FB9724671": sawMayBegin,
            "firstPhases": firstPhases,
            "note": "operating budget = frozen <=5% of the MEASURED disable threshold "
                  + "(dwell-sweep) and <=~1ms; the full adversarial matrix runs on hardware.",
        ])
    }
}
