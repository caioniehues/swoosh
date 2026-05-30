import Foundation
import CoreFoundation
import Darwin

/// U2 — S2: finger count from the private `MultitouchSupport` framework.
///
/// Resolves the symbols via `dlsym` (KTD2), enumerates devices, and — in listen
/// mode — registers a contact-frame callback on a dedicated `CFRunLoop` thread
/// that writes the live contact count to the relaxed atomic (KTD8) the tap
/// thread (U3) reads. The `numTouches` callback argument is the finger count;
/// per-`MTTouch`-field decoding is deliberately avoided (not ABI-stable).
///
/// Permission boundary: `enumerate()` does not consume input (no Input
/// Monitoring needed); `startListening()` does — that path is the real S2 proof
/// and the KTD6 "is Input Monitoring required on this OS?" measurement.
final class MultitouchClient {
    typealias DeviceRef = UnsafeMutableRawPointer
    typealias ContactCallback = @convention(c)
        (DeviceRef?, UnsafeMutablePointer<MTTouch>?, Int32, Double, Int32, UnsafeMutableRawPointer?) -> Void

    private typealias CreateListFn  = @convention(c) () -> Unmanaged<CFArray>?
    private typealias IsBuiltInFn   = @convention(c) (DeviceRef?) -> Bool
    private typealias GetDeviceIDFn = @convention(c) (DeviceRef?, UnsafeMutablePointer<UInt64>?) -> Int32
    private typealias RegisterFn    = @convention(c) (DeviceRef?, ContactCallback, UnsafeMutableRawPointer?) -> Void
    private typealias StartFn       = @convention(c) (DeviceRef?, Int32) -> Void
    private typealias StopFn        = @convention(c) (DeviceRef?) -> Void

    struct Device { let ref: DeviceRef; let builtIn: Bool; let deviceID: UInt64 }

    /// Shared relaxed atomic — written here (sole writer), read by the tap (U3).
    let fingerCount = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
    private(set) var devices: [Device] = []
    private(set) var framesSeen = 0
    private(set) var maxCount: Int32 = 0

    private let handle: UnsafeMutableRawPointer
    private let createList: CreateListFn
    private let isBuiltIn: IsBuiltInFn
    private let getDeviceID: GetDeviceIDFn?
    private let register: RegisterFn
    private let start: StartFn
    private let stop: StopFn
    private let log: DecisionLog
    private var lastCount: Int32 = -1

    init?(log: DecisionLog) {
        self.log = log
        fingerCount.initialize(to: 0)
        guard let h = dlopen(PrivateSymbols.frameworkPath, RTLD_LAZY) else { return nil }
        // `sym` closes over the LOCAL handle `h`, not `self.handle` — calling it
        // before the stored properties are assigned would otherwise trip Swift's
        // definite-initialization check (no partial `self` use pre-init).
        func sym<T>(_ name: String) -> T? {
            guard let p = dlsym(h, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        guard let cl: CreateListFn = sym("MTDeviceCreateList"),
              let ib: IsBuiltInFn = sym("MTDeviceIsBuiltIn"),
              let rg: RegisterFn = sym("MTRegisterContactFrameCallbackWithRefcon"),
              let st: StartFn = sym("MTDeviceStart"),
              let sp: StopFn = sym("MTDeviceStop")
        else { return nil }
        handle = h
        createList = cl; isBuiltIn = ib; register = rg; start = st; stop = sp
        getDeviceID = sym("MTDeviceGetDeviceID")
    }

    /// List all multitouch devices (built-in + external). Does not start the
    /// input stream, so it neither consumes input nor triggers Input Monitoring.
    @discardableResult
    func enumerate() -> [Device] {
        guard let array = createList()?.takeRetainedValue() else {
            log.record("mt.enumerate", ["ok": false, "reason": "MTDeviceCreateList returned nil"])
            return []
        }
        var result: [Device] = []
        for i in 0..<CFArrayGetCount(array) {
            guard let raw = CFArrayGetValueAtIndex(array, i) else { continue }
            let ref = UnsafeMutableRawPointer(mutating: raw)
            var id: UInt64 = 0
            if let getID = getDeviceID { _ = getID(ref, &id) }
            result.append(Device(ref: ref, builtIn: isBuiltIn(ref), deviceID: id))
        }
        devices = result
        log.record("mt.enumerate", [
            "ok": true,
            "count": result.count,
            "builtIn": result.filter { $0.builtIn }.count,
            "external": result.filter { !$0.builtIn }.count,
            "deviceIDs": result.map { String($0.deviceID) },
        ])
        return result
    }

    // The contact callback must be @convention(c) with no captures; it recovers
    // `self` from the refcon and writes the atomic. This is the hot path — it
    // does the minimum: store the count, note transitions.
    private static let callback: ContactCallback = { _, _, numTouches, timestamp, _, refcon in
        guard let refcon else { return }
        let client = Unmanaged<MultitouchClient>.fromOpaque(refcon).takeUnretainedValue()
        let count = max(0, numTouches)
        m0_atomic_store_relaxed(client.fingerCount, count)
        client.onFrame(count: count, timestamp: timestamp)
    }

    private func onFrame(count: Int32, timestamp: Double) {
        framesSeen += 1
        if count > maxCount { maxCount = count }
        if count != lastCount {
            lastCount = count
            log.record("mt.count", ["count": Int(count), "ts": timestamp])
        }
    }

    /// Start the contact-frame stream on a dedicated `CFRunLoop` thread. This
    /// consumes input and requires Input Monitoring — the real S2 path. The
    /// callback fires on the thread that calls `MTDeviceStart`, so it must own a
    /// running runloop (if the thread exits, frames stop).
    func startListening() {
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let thread = Thread { [self] in
            for device in devices {
                register(device.ref, MultitouchClient.callback, selfPtr)
                start(device.ref, 0)
            }
            CFRunLoopRun()
        }
        thread.name = "swoosh.mt"
        thread.stackSize = 1 << 20
        thread.start()
    }

    func stopListening() {
        for device in devices { stop(device.ref) }
    }
}
