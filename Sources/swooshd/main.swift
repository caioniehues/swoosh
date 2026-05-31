import CoreFoundation
import Foundation
import SwooshKit

// swooshd — the Swoosh daemon (SPEC §6 composition-root entry point).
//
// Wires Layer 2 (finger count: MultitouchSupport primary → NSEvent Plan B fallback), the
// off-thread geometry cache (Layer 3), and the session event tap (Layer 1). Running it requires
// Accessibility (and currently Input Monitoring for the live MultitouchSupport stream — KTD6 is
// the open question). This is the M1 scaffold: it proves suppression end-to-end; the
// gesture→snap mapping is wired in M2.

func log(_ message: String) {
    FileHandle.standardError.write(Data("swoosh: \(message)\n".utf8))
}

// Layer 2 with graceful fallback to the specced Plan B (DERISK §5).
let fingers: FingerCountSource
do {
    fingers = try MultitouchClient()
    log("finger-count via MultitouchSupport (primary)")
} catch {
    fingers = NSEventFingerCount()
    log("MultitouchSupport unavailable (\(error)); using NSEvent Plan B")
}

let settings = SettingsStore().load()

let capture: CaptureSink? = CaptureSink.isEnabled ? CaptureSink() : nil
if capture != nil { log("capture mode ON (defaults key '\(CaptureSink.defaultsKey)')") }

// Haptics (SPEC §4.4): available only when the finger source can actuate (MultitouchSupport).
let haptics: HapticEngine? = (fingers as? HapticActuator).map {
    HapticEngine(actuator: $0, enabled: settings.hapticsEnabled)
}
log(haptics?.isAvailable == true ? "haptics available (MTActuator)" : "haptics unavailable")

let service = GestureService(fingers: fingers, capture: capture, haptics: haptics, settings: settings)

// Accessibility gate (SPEC §8): prompt + poll on the main runloop, start the tap once trusted.
let permissions = PermissionService()
func startService() {
    do { try service.start(); log("running (Ctrl-C to stop)") }
    catch { log("failed to start: \(error)"); exit(1) }
}
if permissions.isNativeEdgeTilingEnabled {
    log("note: macOS native edge tiling is on — it fights Swoosh's snaps (SPEC §8)")
}
if permissions.isAccessibilityTrusted {
    startService()
} else {
    log("Accessibility not granted — prompting; polling until trusted (SPEC §8)")
    permissions.requestAccessibility()
    permissions.pollUntilTrusted { startService() }
}

// Graceful teardown on Ctrl-C / SIGTERM.
func installSignalHandler(_ sig: Int32) -> DispatchSourceSignal {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler {
        service.stop()
        if let capture {
            let url = URL(fileURLWithPath: "swoosh-capture.json")
            let os = "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
            if let count = try? capture.flush(to: url, name: "capture", osVersion: os, capturedAt: "session") {
                log("flushed \(count) captured samples to \(url.path)")
            }
        }
        let s = service.latency.summary()
        log("callback latency ms — p50 \(s.p50) p95 \(s.p95) p99 \(s.p99) p999 \(s.p999) max \(s.max) (n=\(s.count))")
        exit(0)
    }
    src.resume()
    return src
}
let sigint = installSignalHandler(SIGINT)
let sigterm = installSignalHandler(SIGTERM)
_ = (sigint, sigterm)   // keep the sources alive

CFRunLoopRun()
