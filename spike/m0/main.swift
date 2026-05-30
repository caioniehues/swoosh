import Foundation
import ApplicationServices   // AXIsProcessTrusted()
import IOKit.hid             // IOHIDCheckAccess()

// =====================================================================
// Swoosh M0 de-risk spike — entry point (THROWAWAY, deleted at the gate).
//
// One bare swiftc-built arm64 binary. The first CLI arg selects a probe;
// each probe writes structured measurements to the JSONL decision log.
//
//   m0spike scaffold     U1 — build/load/struct/atomic/TCC smoke (this file)
//   (m0spike fingers)    U2 — MultitouchSupport finger count   [pending]
//   (m0spike suppress)   U3 — CGEventTap capture & suppression [pending]
//   (m0spike axact)      U4 — off-thread AX locate + write     [pending]
//   (m0spike haptics)    U5 — MTActuator background actuation  [pending]
//
// The full S1–S4 gate resolves only on real macOS 14/15/26 hardware with an
// external trackpad and the Accessibility + Input Monitoring grants the user
// approves interactively. This machine covers the macOS-26 cell.
// =====================================================================

let arguments = CommandLine.arguments
let probe = arguments.count > 1 ? arguments[1] : "scaffold"

let logPath = ProcessInfo.processInfo.environment["M0_LOG"]
    ?? "\(NSTemporaryDirectory())swoosh-m0.jsonl"
let log = DecisionLog(path: logPath)

func osVersionString() -> String {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
}

/// Current TCC posture. These calls only REPORT state — they do not request a
/// grant (which is an interactive System Settings step). This seeds the KTD6
/// "is Input Monitoring actually required?" measurement that U2 completes.
func tccState() -> (accessibility: Bool, inputMonitoring: String) {
    let accessibility = AXIsProcessTrusted()
    let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
    let inputMonitoring: String
    switch access {
    case kIOHIDAccessTypeGranted: inputMonitoring = "granted"
    case kIOHIDAccessTypeDenied:  inputMonitoring = "denied"
    default:                      inputMonitoring = "unknown"
    }
    return (accessibility, inputMonitoring)
}

/// U1 — prove the spike builds, the private framework opens, every required
/// symbol resolves, the MTTouch ABI hasn't drifted, and the relaxed atomic
/// round-trips. None of this needs a TCC grant, so it runs unattended on 26.
@discardableResult
func runScaffold() -> Bool {
    log.record("scaffold.start", ["os": osVersionString(), "arch": "arm64"])

    // (1) sizeof(MTTouch) drift guard — the R17 tripwire.
    let touchSize = MemoryLayout<MTTouch>.size
    let sizeOK = (touchSize == 96)
    log.record("struct.MTTouch.sizeof",
               ["bytes": touchSize, "expected": 96, "ok": sizeOK])

    // (2) dlopen + dlsym the private framework (KTD2).
    let symbols = PrivateSymbols.probe()
    log.record("dlopen.MultitouchSupport", [
        "opened": symbols.handleOpened,
        "resolvedCount": symbols.resolved.count,
        "requiredCount": PrivateSymbols.required.count,
        "missing": symbols.missing,
        "allResolved": symbols.allResolved,
    ])

    // (3) relaxed lock-free atomic round-trip (KTD8 primitive).
    let counter = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
    counter.initialize(to: 0)
    defer { counter.deallocate() }
    m0_atomic_store_relaxed(counter, 2)
    let readBack = m0_atomic_load_relaxed(counter)
    let atomicOK = (readBack == 2)
    log.record("atomic.relaxed.roundtrip",
               ["wrote": 2, "read": Int(readBack), "ok": atomicOK])

    // (4) current TCC posture (seed for the KTD6 measurement).
    let tcc = tccState()
    log.record("tcc.state", [
        "accessibility": tcc.accessibility,
        "inputMonitoring": tcc.inputMonitoring,
    ])

    let pass = sizeOK && symbols.handleOpened && atomicOK
    log.record("scaffold.result", [
        "pass": pass,
        "note": "U1 proves build/load/struct/atomic on this OS only; the S1-S4 "
              + "gate needs macOS 14/15/26 + interactive grants + a trackpad.",
    ])
    return pass
}

switch probe {
case "scaffold":
    exit(runScaffold() ? 0 : 1)
default:
    log.record("error.unknownProbe", ["probe": probe])
    FileHandle.standardError.write(Data("unknown probe: \(probe)\n".utf8))
    exit(2)
}
