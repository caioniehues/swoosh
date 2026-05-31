import CoreFoundation
import Darwin
import Foundation
import Synchronization

/// Layer 2 primary (SPEC §7, ported from the M0 spike). Loads the private
/// `MultitouchSupport.framework` at runtime via `dlopen`/`dlsym` — **never** linked (arm64e
/// PAC turns direct linkage into a bus error, KTD2) — enumerates devices, writes the live
/// contact count to a lock-free atomic the tap thread reads, and (M3) actuates the private
/// `MTActuator` haptics confirmed load-bearing by M0.
///
/// This is the **only** place private-framework loading is allowed (the CLAUDE.md / SPEC §7
/// confinement rule, enforced by a CI ast-grep rule); the `MTActuator` symbols live here too so
/// that all private SPI resolution stays in one auditable file.
public final class MultitouchClient: FingerCountSource, HapticActuator {
    private typealias DeviceRef = UnsafeMutableRawPointer
    private typealias ContactCallback = @convention(c)
        (DeviceRef?, UnsafeRawPointer?, Int32, Double, Int32, UnsafeMutableRawPointer?) -> Void
    private typealias CreateListFn  = @convention(c) () -> Unmanaged<CFArray>?
    private typealias IsBuiltInFn   = @convention(c) (DeviceRef?) -> Bool
    private typealias GetDeviceIDFn = @convention(c) (DeviceRef?, UnsafeMutablePointer<UInt64>?) -> Int32
    private typealias RegisterFn    = @convention(c) (DeviceRef?, ContactCallback, UnsafeMutableRawPointer?) -> Void
    private typealias StartFn       = @convention(c) (DeviceRef?, Int32) -> Void
    private typealias StopFn        = @convention(c) (DeviceRef?) -> Void
    // MTActuator family (haptics, SPEC §4.4). The actuator ref is an opaque CFType; treated as a
    // raw pointer here since we only create→open→actuate→close it.
    private typealias ActuatorCreateFn  = @convention(c) (UInt64) -> UnsafeMutableRawPointer?
    private typealias ActuatorOpenFn    = @convention(c) (UnsafeMutableRawPointer?) -> Int32  // IOReturn
    private typealias ActuatorActuateFn = @convention(c) (UnsafeMutableRawPointer?, Int32, UInt32, Float, Float) -> Int32
    private typealias ActuatorCloseFn   = @convention(c) (UnsafeMutableRawPointer?) -> Int32

    public static let frameworkPath =
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

    private struct Device { let ref: DeviceRef; let builtIn: Bool; let deviceID: UInt64 }

    /// Single-writer (MT callback thread) / single-reader (tap thread), relaxed ordering —
    /// the macOS-26-only payoff that replaces the spike's C-shim atomic (KTD8).
    private let fingerCountAtomic = Atomic<Int32>(0)

    private let handle: UnsafeMutableRawPointer
    private let createList: CreateListFn
    private let isBuiltIn: IsBuiltInFn
    private let getDeviceID: GetDeviceIDFn?
    private let register: RegisterFn
    private let startDevice: StartFn
    private let stopDevice: StopFn
    private let actuatorCreate: ActuatorCreateFn?
    private let actuatorOpen: ActuatorOpenFn?
    private let actuatorActuate: ActuatorActuateFn?
    private let actuatorClose: ActuatorCloseFn?

    /// Retained `MTDeviceCreateList` array — MUST outlive the listen session (UAF guard found +
    /// fixed in the M0 spike: releasing it dangles every `MTDeviceRef`).
    private var deviceList: CFArray?
    private var devices: [Device] = []
    private var thread: Thread?
    private var runLoop: CFRunLoop?

    private var builtInDeviceID: UInt64 = 0
    private var actuator: UnsafeMutableRawPointer?

    public init() throws {
        guard let h = dlopen(MultitouchClient.frameworkPath, RTLD_LAZY) else {
            throw FingerCountError.frameworkUnavailable(path: MultitouchClient.frameworkPath)
        }
        func sym<T>(_ name: String) -> T? {
            guard let p = dlsym(h, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        var missing: [String] = []
        let cl: CreateListFn? = sym("MTDeviceCreateList"); if cl == nil { missing.append("MTDeviceCreateList") }
        let ib: IsBuiltInFn?  = sym("MTDeviceIsBuiltIn");  if ib == nil { missing.append("MTDeviceIsBuiltIn") }
        let rg: RegisterFn?   = sym("MTRegisterContactFrameCallbackWithRefcon"); if rg == nil { missing.append("MTRegisterContactFrameCallbackWithRefcon") }
        let st: StartFn?      = sym("MTDeviceStart");      if st == nil { missing.append("MTDeviceStart") }
        let sp: StopFn?       = sym("MTDeviceStop");       if sp == nil { missing.append("MTDeviceStop") }
        guard let cl, let ib, let rg, let st, let sp else {
            dlclose(h)
            throw FingerCountError.missingSymbols(missing)
        }
        handle = h
        createList = cl; isBuiltIn = ib; register = rg; startDevice = st; stopDevice = sp
        getDeviceID = sym("MTDeviceGetDeviceID")
        // Haptics are optional: if any actuator symbol is absent, `supportsHaptics` is false and
        // the engine degrades to silent (SPEC §4.4).
        actuatorCreate  = sym("MTActuatorCreateFromDeviceID")
        actuatorOpen    = sym("MTActuatorOpen")
        actuatorActuate = sym("MTActuatorActuate")
        actuatorClose   = sym("MTActuatorClose")
    }

    // MARK: - FingerCountSource

    public var contactCount: Int {
        Int(fingerCountAtomic.load(ordering: .relaxed))
    }

    private func enumerate() {
        guard let array = createList()?.takeRetainedValue() else { return }
        deviceList = array
        var result: [Device] = []
        for i in 0 ..< CFArrayGetCount(array) {
            guard let raw = CFArrayGetValueAtIndex(array, i) else { continue }
            let ref = UnsafeMutableRawPointer(mutating: raw)
            var id: UInt64 = 0
            if let getID = getDeviceID { _ = getID(ref, &id) }
            result.append(Device(ref: ref, builtIn: isBuiltIn(ref), deviceID: id))
        }
        devices = result
        builtInDeviceID = (result.first { $0.builtIn } ?? result.first)?.deviceID ?? 0
    }

    private static let callback: ContactCallback = { _, _, numTouches, _, _, refcon in
        guard let refcon else { return }
        let client = Unmanaged<MultitouchClient>.fromOpaque(refcon).takeUnretainedValue()
        client.fingerCountAtomic.store(max(0, numTouches), ordering: .relaxed)
    }

    public func start() throws {
        enumerate()
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let t = Thread { [self] in
            runLoop = CFRunLoopGetCurrent()
            for device in devices {
                register(device.ref, MultitouchClient.callback, selfPtr)
                startDevice(device.ref, 0)
            }
            CFRunLoopRun()
        }
        t.name = "swoosh.mt"
        t.stackSize = 1 << 20
        thread = t
        t.start()
    }

    public func stop() {
        for device in devices { stopDevice(device.ref) }
        if let runLoop { CFRunLoopStop(runLoop) }
        thread = nil
        fingerCountAtomic.store(0, ordering: .relaxed)
        if let a = actuator, let close = actuatorClose { _ = close(a); actuator = nil }
    }

    // MARK: - HapticActuator (SPEC §4.4)

    public var supportsHaptics: Bool {
        actuatorCreate != nil && actuatorOpen != nil && actuatorActuate != nil
    }

    /// Fire a haptic tap (actuationID 1–6 are the cross-confirmed safe set; 2 = strong click).
    /// Lazily creates + opens the actuator for the built-in device and reuses it.
    public func actuate(_ actuationID: Int32) {
        guard let create = actuatorCreate, let open = actuatorOpen, let act = actuatorActuate,
              builtInDeviceID != 0 else { return }
        if actuator == nil {
            actuator = create(builtInDeviceID)
            if let a = actuator { _ = open(a) }
        }
        if let a = actuator { _ = act(a, actuationID, 0, 0.0, 0.0) }
    }
}
