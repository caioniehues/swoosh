import CoreGraphics
import Foundation
import SwooshCore

/// The composition root that wires Layers 1–4 (SPEC §6). On the tap thread it builds a
/// `RecognizerInput` from the finger-count atomic (L2) + the scroll phase (L1) + the
/// off-thread geometry cache (L3), runs the **same pure `Recognizer` the headless replayer
/// tests** (the DERISK §3 seam), and on suppress hands off to the AX act path (L4) off-thread.
public final class GestureService {
    private let fingers: FingerCountSource
    private let cache: WindowGeometryCache
    private let applier: SnapApplier
    private let capture: CaptureSink?
    private var tap: EventTap!
    private let haptics: HapticEngine?
    private let settings: SwooshSettings
    /// Accumulates the current two-finger swipe (tap-thread state; the tap is single-threaded).
    private var gesture: SwipeGesture
    /// Whether the "ready" tap has fired for the current gesture (fire once per gesture).
    private var readyFired = false
    /// Active divider-drag resize session (SPEC §4.3), or nil when not dragging a divider.
    private var dividerSession: WindowGeometryCache.DividerHit?

    public init(
        fingers: FingerCountSource,
        cache: WindowGeometryCache = WindowGeometryCache(),
        applier: SnapApplier = SnapApplier(),
        capture: CaptureSink? = nil,
        haptics: HapticEngine? = nil,
        settings: SwooshSettings = .default
    ) {
        self.fingers = fingers
        self.cache = cache
        self.applier = applier
        self.capture = capture
        self.haptics = haptics
        self.settings = settings
        self.gesture = SwipeGesture(commitThreshold: settings.commitThreshold)
        let mask = EventTap.mask(for: [.scrollWheel, .leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown])
        self.tap = EventTap(mask: mask) { [weak self] type, event in
            guard let self else { return event }   // service gone → pass everything through
            switch type {
            case .scrollWheel:
                return self.decide(event)
            case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
                return self.handleMouse(type, event)
            case .keyDown:
                return self.handleKey(event)
            default:
                return event
            }
        }
    }

    /// Start order: finger stream → geometry cache → tap (so the tap reads live data immediately).
    public func start() throws {
        try fingers.start()
        cache.start()
        try tap.enable()
    }

    /// Strict teardown order (M0 plan): disable the tap first, then stop producers.
    public func stop() {
        tap.disable()
        cache.stop()
        fingers.stop()
    }

    public var latency: LatencyStats { tap.latency }

    /// The synchronous tap-thread decision (SPEC §6.2) plus swipe-gesture tracking. Returns the
    /// event to pass, or `nil` to suppress.
    func decide(_ event: CGEvent) -> CGEvent? {
        let cursor = event.location
        let phase = ScrollPhase(rawValue: Int(event.getIntegerValueField(.scrollWheelEventScrollPhase))) ?? .none
        let input = RecognizerInput(
            contactCount: fingers.contactCount,
            phase: phase,
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) == 1,
            cursor: cursor,
            titlebarBand: cache.titlebarBand(at: cursor)
        )
        let decision = Recognizer.decide(input)
        capture?.record(input: input, decision: decision)

        // Track the swipe only while it is ours (a suppressed titlebar pan) and commit on end
        // (SPEC §4.1). The accumulator + direction→target resolution are the pure M2 recognizer;
        // the AX state classification + write happen off-thread in SnapApplier.
        switch phase {
        case .began where decision == .suppress:
            gesture.reset()
            readyFired = false
            gesture.add(phase: .began, delta: scrollDelta(event))
        case .changed where decision == .suppress:
            gesture.add(phase: .changed, delta: scrollDelta(event))
            if !readyFired, gesture.committedDirection(diagonalThreshold: settings.diagonalThreshold) != nil {
                readyFired = true
                haptics?.ready()   // crossed the commit threshold — "ready" tap (SPEC §4.4)
            }
        case .ended, .cancelled:
            if gesture.isActive {
                if phase == .ended,
                   let direction = gesture.committedDirection(diagonalThreshold: settings.diagonalThreshold) {
                    haptics?.done()   // committed — "done" tap; never fires on cancel
                    applier.enqueueSwipe(direction, at: cursor)
                }
                gesture.reset()
                readyFired = false
            }
        default:
            break
        }

        return decision == .suppress ? nil : event
    }

    /// Map a CG scroll event's deltas to the engine convention (+x right, +y up). The point-delta
    /// sign depends on hardware and the "natural scrolling" setting; calibrate on real hardware
    /// (a future setting). Vertical is negated so a physical upward swipe reads as +y.
    private func scrollDelta(_ event: CGEvent) -> CGVector {
        let vertical = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let horizontal = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        return CGVector(dx: CGFloat(horizontal), dy: CGFloat(-vertical))
    }

    /// Divider-drag modality (SPEC §4.3): a left-mouse drag, not a scroll. On down, a fast
    /// geometry check (no AX) decides whether the cursor sits on a shared snapped edge; if so the
    /// drag is consumed and resizes both windows in lockstep until mouse-up. Otherwise it passes
    /// through untouched, so ordinary clicks and drags are unaffected.
    func handleMouse(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        let cursor = event.location
        switch type {
        case .leftMouseDown:
            if let hit = cache.dividerHit(at: cursor) {
                dividerSession = hit
                return nil   // consume — begin the resize session
            }
            return event
        case .leftMouseDragged:
            guard let hit = dividerSession else { return event }
            let position = hit.divider.orientation == .vertical ? cursor.x : cursor.y
            applier.enqueueDividerResize(leading: hit.leadingFrame, trailing: hit.trailingFrame,
                                         orientation: hit.divider.orientation, to: position)
            return nil
        case .leftMouseUp:
            if dividerSession != nil { dividerSession = nil; return nil }
            return event
        default:
            return event
        }
    }

    /// Keyboard shortcut modality (SPEC §4.5). A bound chord acts on the FOCUSED window and is
    /// consumed; anything unbound passes through so normal typing is unaffected.
    func handleKey(_ event: CGEvent) -> CGEvent? {
        guard let chord = KeyCodeMap.chord(from: event),
              let action = KeyBindings.action(for: chord) else { return event }
        switch action {
        case .swipe(let direction): applier.enqueueSwipeFocused(direction)
        case .snap(let target):     applier.enqueueApplyFocused(target)
        case .restore:              applier.enqueueApplyFocused(.restore)
        case .exitFullscreen:       applier.enqueueExitFullscreenFocused()
        }
        return nil   // consume the bound shortcut
    }
}
