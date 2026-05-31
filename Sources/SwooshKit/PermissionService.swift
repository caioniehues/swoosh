import ApplicationServices
import Foundation

/// The permission + conflict-detection flow (SPEC §8). Requests **Accessibility only** (least
/// privilege, STRATEGY §5); polls until granted, then signals the daemon to start the tap.
public final class PermissionService {
    private var pollTimer: DispatchSourceTimer?

    public init() {}

    /// Whether Accessibility is granted (no prompt).
    public var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Trigger the system Accessibility prompt (SPEC §8 onboarding step).
    @discardableResult
    public func requestAccessibility() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    /// Poll `AXIsProcessTrusted` every `interval` seconds; call `onGranted` on the main queue
    /// once granted, then stop (SPEC §8: "Poll AXIsProcessTrustedWithOptions every 1s").
    public func pollUntilTrusted(interval: TimeInterval = 1, onGranted: @escaping () -> Void) {
        if isAccessibilityTrusted { onGranted(); return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if self.isAccessibilityTrusted {
                timer.cancel()
                self.pollTimer = nil
                onGranted()
            }
        }
        pollTimer = timer
        timer.resume()
    }

    /// Whether macOS native edge-drag tiling is enabled (SPEC §8: it fights Swoosh's snaps, so
    /// onboarding offers to disable it). The key lives in the WindowManager domain; recent macOS
    /// defaults it on when unset. (Key name to confirm on macOS 26 hardware.)
    public var isNativeEdgeTilingEnabled: Bool {
        guard let wm = UserDefaults(suiteName: "com.apple.WindowManager") else { return false }
        return wm.object(forKey: "EnableTilingByEdgeDrag") as? Bool ?? true
    }
}
