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

/// U2 — S2: finger count. `fingers` enumerates devices (safe, no Input
/// Monitoring). `M0_LISTEN=1 ... fingers` additionally starts the contact stream
/// (needs Input Monitoring + physical touch) — the real S2 / KTD6 measurement.
func runFingers() -> Bool {
    log.record("fingers.start", ["os": osVersionString()])
    let before = tccState()
    log.record("tcc.before", [
        "accessibility": before.accessibility,
        "inputMonitoring": before.inputMonitoring,
    ])
    guard let client = MultitouchClient(log: log) else {
        log.record("fingers.result", ["pass": false, "reason": "load/resolve MultitouchSupport failed"])
        return false
    }
    let devices = client.enumerate()

    guard ProcessInfo.processInfo.environment["M0_LISTEN"] == "1" else {
        log.record("fingers.result", [
            "mode": "enumerate-only",
            "devices": devices.count,
            "pass": !devices.isEmpty,
            "note": "set M0_LISTEN=1 to start the contact stream (Input Monitoring + two-finger touch).",
        ])
        return !devices.isEmpty
    }

    // Listen mode — run by the user on real hardware with a trackpad.
    client.startListening()
    let seconds = 6.0
    log.record("fingers.listening",
               ["seconds": seconds, "instruction": "touch the trackpad with two fingers now"])
    Thread.sleep(forTimeInterval: seconds)
    client.stopListening()
    let after = tccState()
    log.record("fingers.result", [
        "mode": "listen",
        "framesSeen": client.framesSeen,
        "maxFingers": Int(client.maxCount),
        "tccAfter_inputMonitoring": after.inputMonitoring,
        "pass": client.framesSeen > 0,
        "note": "KTD6: compare frames-arrive with Input Monitoring granted vs revoked.",
    ])
    return client.framesSeen > 0
}

/// U3 — S1: capture & suppress. Default is a dry, dialog-free build check.
/// `M0_TAP=1 ... suppress` installs the active session tap (needs Accessibility;
/// may prompt). `M0_DWELL_MS=<n>` runs the disable-threshold dwell-sweep. For
/// live finger data, run a `M0_LISTEN=1 ... fingers` listener alongside.
func runSuppress() -> Bool {
    log.record("suppress.start", ["os": osVersionString(), "axTrusted": AXIsProcessTrusted()])

    // Combined mode (M0_LISTEN=1): start the real MultitouchSupport contact
    // stream IN THIS PROCESS so the tap reads a LIVE finger count through the one
    // shared KTD8 atomic. Without this, `suppress` reads a private zeroed counter
    // nothing ever writes — fingers==2 can never fire, so it installs the tap and
    // logs timing but never swallows an event (the TESTING.md S1 caveat). The MT
    // callback (sole writer) and the tap callback (sole reader) run on different
    // threads sharing the same address — exactly the single-writer/single-reader
    // contract the relaxed atomic was chosen for.
    let wantLive = ProcessInfo.processInfo.environment["M0_LISTEN"] == "1"
    var mtClient: MultitouchClient?
    var ownedCounter: UnsafeMutablePointer<Int32>?
    let counter: UnsafePointer<Int32>

    if wantLive, let client = MultitouchClient(log: log) {
        client.enumerate()
        client.startListening()
        mtClient = client
        counter = UnsafePointer(client.fingerCount)   // MT thread writes, tap reads
        log.record("suppress.mode",
                   ["combined": true,
                    "note": "live MultitouchSupport count feeds the tap via the shared KTD8 atomic"])
    } else {
        let c = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        c.initialize(to: 0)
        ownedCounter = c
        counter = UnsafePointer(c)
        if wantLive {
            log.record("suppress.mode",
                       ["combined": false,
                        "note": "M0_LISTEN set but MultitouchClient init failed — finger count stays 0"])
        }
    }
    defer {
        mtClient?.stopListening()
        ownedCounter?.deallocate()
    }

    let probe = EventTapProbe(fingerCount: counter, log: log)
    if let dwell = ProcessInfo.processInfo.environment["M0_DWELL_MS"], let ms = Double(dwell) {
        probe.dwellMillis = ms
    }

    guard ProcessInfo.processInfo.environment["M0_TAP"] == "1" else {
        log.record("suppress.result", [
            "mode": "dry",
            "pass": true,
            "note": "build-validated only; set M0_TAP=1 to install the active session "
                  + "tap (needs Accessibility, may prompt). The S1 gate runs on hardware.",
        ])
        return true
    }

    guard probe.install() else {
        log.record("suppress.result", ["mode": "tap", "pass": false, "reason": "tap not created"])
        return false
    }
    // Window override so the combined run can give a human time to rest two
    // fingers AND pan a titlebar in one pass; defaults to the prior 8s.
    let seconds = ProcessInfo.processInfo.environment["M0_SECONDS"].flatMap(Double.init) ?? 8.0
    log.record("suppress.listening",
               ["seconds": seconds,
                "live": wantLive,
                "instruction": wantLive
                    ? "rest TWO fingers and pan a window titlebar; then normal scroll elsewhere"
                    : "two-finger pan on a window titlebar, then normal scroll elsewhere"])
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2))
    }
    probe.report()
    log.record("suppress.result",
               ["mode": wantLive ? "tap+live" : "tap", "pass": true,
                "liveMaxFingers": Int(mtClient?.maxCount ?? 0),
                "liveFramesSeen": mtClient?.framesSeen ?? 0,
                "note": wantLive
                    ? "inspect tap.summary.suppressed; live finger count fed the tap"
                    : "inspect tap.summary; add M0_LISTEN=1 for live finger counts (combined S1 test)"])
    return true
}

/// U4 — S3: off-thread AX locate + move/resize. Default is a dry build check.
/// `M0_AX=1 ... axact` runs the self-test against the window under the cursor
/// (needs Accessibility; may prompt). Move the cursor over a window titlebar first.
func runAXAct() -> Bool {
    log.record("axact.start", ["os": osVersionString(), "axTrusted": AXIsProcessTrusted()])
    guard ProcessInfo.processInfo.environment["M0_AX"] == "1" else {
        log.record("axact.result", [
            "mode": "dry",
            "pass": true,
            "note": "build-validated only; set M0_AX=1 to run the AX move/resize self-test "
                  + "(needs Accessibility, may prompt). The S3 gate runs on hardware.",
        ])
        return true
    }
    AXActProbe(log: log).runSelfTest()
    log.record("axact.result", ["mode": "ax", "pass": true, "note": "inspect ax.window / ax.write."])
    return true
}

/// U5 — S4: MTActuator background haptics. Default enumerates + checks the
/// actuator symbols (no buzz). `M0_HAPTIC=1 ... haptics` physically actuates the
/// trackpad — the only ground truth is whether you FEEL the tap.
func runHaptics() -> Bool {
    log.record("haptics.start", ["os": osVersionString()])
    guard let mt = MultitouchClient(log: log) else {
        log.record("haptics.result", ["pass": false, "reason": "MultitouchSupport load failed"])
        return false
    }
    let deviceIDs = mt.enumerate().map { $0.deviceID }.filter { $0 != 0 }
    guard let probe = HapticProbe(log: log) else {
        log.record("haptics.result", ["pass": false, "reason": "MTActuator symbols missing"])
        return false
    }
    log.record("haptics.ready", ["devicesWithID": deviceIDs.count])

    guard ProcessInfo.processInfo.environment["M0_HAPTIC"] == "1" else {
        log.record("haptics.result", [
            "mode": "dry",
            "pass": true,
            "devicesWithID": deviceIDs.count,
            "note": "set M0_HAPTIC=1 to actuate (physically buzzes the trackpad). The public "
                  + "NSHapticFeedbackManager path is not attempted (KTD3).",
        ])
        return true
    }
    let fired = probe.actuateAll(deviceIDs: deviceIDs)
    log.record("haptics.result",
               ["mode": "actuate", "pass": fired,
                "note": "did you FEEL a tap? that physical sensation is the real S4 oracle."])
    return fired
}

switch probe {
case "scaffold":
    exit(runScaffold() ? 0 : 1)
case "fingers":
    exit(runFingers() ? 0 : 1)
case "suppress":
    exit(runSuppress() ? 0 : 1)
case "axact":
    exit(runAXAct() ? 0 : 1)
case "haptics":
    exit(runHaptics() ? 0 : 1)
default:
    log.record("error.unknownProbe", ["probe": probe])
    FileHandle.standardError.write(Data("unknown probe: \(probe)\n".utf8))
    exit(2)
}
