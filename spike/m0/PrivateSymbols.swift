import Darwin

/// Runtime loader for the private `MultitouchSupport.framework` (plan KTD2).
///
/// On Apple Silicon (arm64e pointer authentication), these symbols MUST be
/// reached via `dlopen`/`dlsym` — direct linkage or `-framework` causes a bus
/// error. The spike therefore never links the framework; it opens it at runtime
/// and resolves each symbol by name. U1 only proves the symbols *resolve*; U2
/// (finger count) and U5 (haptics) bind and call them.
enum PrivateSymbols {
    static let frameworkPath =
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

    /// Symbols the later probes depend on, grouped by consumer.
    static let required: [String] = [
        // Device enumeration + lifecycle (U2 — finger count).
        "MTDeviceCreateList",
        "MTDeviceCreateDefault",
        "MTDeviceCreateFromDeviceID",
        "MTDeviceGetDeviceID",
        "MTDeviceIsBuiltIn",
        "MTRegisterContactFrameCallback",
        "MTRegisterContactFrameCallbackWithRefcon",
        "MTDeviceStart",
        "MTDeviceStop",
        // Haptic actuation (U5).
        "MTActuatorCreateFromDeviceID",
        "MTActuatorOpen",
        "MTActuatorActuate",
        "MTActuatorClose",
        "MTActuatorIsOpen",
    ]

    struct LoadResult {
        let handleOpened: Bool
        let resolved: [String]
        let missing: [String]
        var allResolved: Bool { handleOpened && missing.isEmpty }
    }

    /// Opens the framework and reports which required symbols resolve.
    /// Does not `dlclose`: the loaded image is reused for the rest of the run.
    static func probe() -> LoadResult {
        guard let handle = dlopen(frameworkPath, RTLD_LAZY) else {
            return LoadResult(handleOpened: false, resolved: [], missing: required)
        }
        var resolved: [String] = []
        var missing: [String] = []
        for symbol in required {
            if dlsym(handle, symbol) != nil { resolved.append(symbol) }
            else { missing.append(symbol) }
        }
        return LoadResult(handleOpened: true, resolved: resolved, missing: missing)
    }
}
