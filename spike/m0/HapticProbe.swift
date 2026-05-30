import Foundation
import CoreFoundation
import Darwin

/// U5 — S4: background haptic actuation via the private `MTActuator` family.
///
/// The public `NSHapticFeedbackManager` path is deliberately NOT attempted
/// (KTD3): Apple silences it for non-frontmost processes by design, confirmed
/// by BetterTouchTool's identical background-daemon failure. Device IDs come
/// from `MultitouchClient.enumerate()` (U2); U1 confirmed every `MTActuator`
/// symbol resolves on macOS 26.
///
/// Critical honesty: `IOReturn == kIOReturnSuccess` is necessary but NOT
/// sufficient — a wrong waveform argument can return success yet produce no felt
/// tap, so the human feeling for it is the real S4 oracle. And this bare binary
/// has no `NSApplication`, so a success proves actuation-on-hardware, not the
/// product's eventual background-*agent* frontmost case (re-validated in M3).
final class HapticProbe {
    private typealias CreateFromIDFn = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
    private typealias OpenFn    = @convention(c) (CFTypeRef) -> Int32   // IOReturn
    private typealias ActuateFn = @convention(c) (CFTypeRef, Int32, UInt32, Float, Float) -> Int32
    private typealias CloseFn   = @convention(c) (CFTypeRef) -> Int32

    private let createFromID: CreateFromIDFn
    private let open: OpenFn
    private let actuate: ActuateFn
    private let close: CloseFn
    private let log: DecisionLog

    init?(log: DecisionLog) {
        self.log = log
        guard let h = dlopen(PrivateSymbols.frameworkPath, RTLD_LAZY) else { return nil }
        func sym<T>(_ name: String) -> T? {
            guard let p = dlsym(h, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        guard let c: CreateFromIDFn = sym("MTActuatorCreateFromDeviceID"),
              let o: OpenFn = sym("MTActuatorOpen"),
              let a: ActuateFn = sym("MTActuatorActuate"),
              let cl: CloseFn = sym("MTActuatorClose")
        else { return nil }
        createFromID = c; open = o; actuate = a; close = cl
    }

    /// Actuate `actuationID` (default 2 = strong click; 1–6 are the cross-source
    /// safe set) on each device. Returns whether any device reported success.
    @discardableResult
    func actuateAll(deviceIDs: [UInt64], actuationID: Int32 = 2) -> Bool {
        guard !deviceIDs.isEmpty else {
            log.record("haptic.actuate", ["ok": false, "reason": "no devices with a valid ID"])
            return false
        }
        var anyFired = false
        for id in deviceIDs {
            guard let ref = createFromID(id)?.takeRetainedValue() else {
                log.record("haptic.actuate",
                           ["deviceID": String(id), "ok": false, "reason": "MTActuatorCreateFromDeviceID nil"])
                continue
            }
            let openReturn = open(ref)
            let actuateReturn = actuate(ref, actuationID, 0, 0.0, 0.0)
            let closeReturn = close(ref)
            let ok = (openReturn == 0 && actuateReturn == 0)
            if ok { anyFired = true }
            log.record("haptic.actuate", [
                "deviceID": String(id),
                "actuationID": Int(actuationID),
                "openIOReturn": Int(openReturn),
                "actuateIOReturn": Int(actuateReturn),
                "closeIOReturn": Int(closeReturn),
                "ok": ok,
                "note": "IOReturn 0 == kIOReturnSuccess; success != felt — confirm by feel.",
            ])
        }
        return anyFired
    }
}
