import Foundation

/// Something that can fire a haptic tap on the trackpad. `MultitouchClient` conforms via the
/// private `MTActuator` path (SPEC §4.4); a non-haptic finger source simply doesn't.
public protocol HapticActuator: AnyObject {
    /// Whether this hardware/path can actuate. When false, the engine stays silent.
    var supportsHaptics: Bool { get }
    /// Fire a tap with the given actuation id (1–6 safe; 2 = strong, 3 = lighter).
    func actuate(_ actuationID: Int32)
}

/// Ready/done haptic taps (SPEC §4.4). Serialized on its own queue and silently no-ops when the
/// hardware has no actuator or haptics are disabled. It never fires on a cancelled gesture
/// because the caller only invokes `done()` on commit.
public final class HapticEngine {
    /// User toggle (SPEC §4.4: configurable). Off automatically when no actuator is present.
    public var isEnabled: Bool

    private let actuator: HapticActuator
    private let queue = DispatchQueue(label: "swoosh.haptic", qos: .userInteractive)

    public init(actuator: HapticActuator, enabled: Bool = true) {
        self.actuator = actuator
        self.isEnabled = enabled
    }

    /// Whether taps will actually fire (enabled AND the hardware supports it).
    public var isAvailable: Bool { isEnabled && actuator.supportsHaptics }

    /// A lighter "ready" tap when a gesture crosses its commit threshold / the grid cursor moves.
    public func ready() { tap(3) }

    /// A firm "done" tap on commit.
    public func done() { tap(2) }

    private func tap(_ id: Int32) {
        guard isEnabled, actuator.supportsHaptics else { return }
        queue.async { [actuator] in actuator.actuate(id) }
    }
}
