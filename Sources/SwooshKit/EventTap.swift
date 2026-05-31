import ApplicationServices   // AXIsProcessTrusted
import CoreGraphics
import Foundation

public enum EventTapError: Error, CustomStringConvertible {
    case creationFailed(trusted: Bool)
    public var description: String {
        switch self {
        case .creationFailed(let trusted):
            return "CGEvent.tapCreate returned nil (AXIsProcessTrusted=\(trusted)). Grant "
                 + "Accessibility; run as a normal (not LSBackgroundOnly) process to dodge the "
                 + "Sequoia NULL regression."
        }
    }
}

/// Layer 1 (SPEC §6 / §9). A session-level `CGEventTap` that observes its event mask and asks a
/// caller-supplied handler to decide pass (return the event) or suppress (return `nil`). It
/// carries both modalities (SPEC §6): scroll-wheel for the swipe pipeline, and left-mouse
/// down/drag/up for divider-drag (§4.3) — the handler routes by `CGEventType`.
///
/// The handler must be **fast and non-blocking** — the tap is disabled if a callback is slow
/// (the `kCGEventTapDisabledByTimeout` ceiling M0 measured) — and is timed for the R9 latency
/// baseline. The disable/re-enable dance (the canonical Hammerspoon pattern) is handled here.
public final class EventTap {
    public typealias Handler = (CGEventType, CGEvent) -> CGEvent?

    /// Scroll-wheel-only mask. A broad scroll mask silently disables the system three-finger
    /// look-up gesture, so the scroll modality is narrowed deliberately (M0 U3 note).
    public static let scrollWheelMask = mask(for: [.scrollWheel])

    /// Scroll + left-mouse down/drag/up — the combined mask for swipe + divider-drag (SPEC §4.3).
    public static let scrollAndDragMask = mask(for: [.scrollWheel, .leftMouseDown, .leftMouseDragged, .leftMouseUp])

    /// Build a `CGEventMask` from event types.
    public static func mask(for types: [CGEventType]) -> CGEventMask {
        types.reduce(0) { $0 | (CGEventMask(1) << UInt64($1.rawValue)) }
    }

    private let mask: CGEventMask
    private let handler: Handler
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    public private(set) var latency = LatencyStats()
    public private(set) var reenableCount = 0

    public init(mask: CGEventMask = EventTap.scrollWheelMask, onEvent: @escaping Handler) {
        self.mask = mask
        self.handler = onEvent
    }

    public var isTrusted: Bool { AXIsProcessTrusted() }

    /// Create + enable the tap and add it to the current runloop. Call on the thread whose
    /// runloop should service the tap (typically the main thread before `CFRunLoopRun`).
    public func enable() throws {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: EventTap.trampoline,
            userInfo: refcon
        ) else {
            throw EventTapError.creationFailed(trusted: AXIsProcessTrusted())
        }
        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = src
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    public func disable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private static let trampoline: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let me = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
        return me.handle(type: type, event: event)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables the tap on a slow callback or secure input — re-arm immediately.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            reenableCount += 1
            return Unmanaged.passUnretained(event)
        }

        let start = DispatchTime.now().uptimeNanoseconds
        let result = handler(type, event)
        latency.record(DispatchTime.now().uptimeNanoseconds - start)

        if let result { return Unmanaged.passUnretained(result) }
        return nil   // suppress
    }
}
