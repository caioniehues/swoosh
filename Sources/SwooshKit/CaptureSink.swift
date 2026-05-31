import Foundation
import os
import SwooshCore
import SwooshFixtures

/// Capture mode (DERISK §2): a hidden runtime toggle, enabled via the `defaults` key
/// `captureMode`, that records what each scroll event's gate saw and decided so it can be
/// replayed later. It ships in release builds so non-developers can record fixtures with no
/// toolchain. Appends are lock-guarded (uncontended → microseconds); the disk flush is off-path.
public final class CaptureSink {
    public static let defaultsKey = "captureMode"

    private let lock = OSAllocatedUnfairLock(initialState: FixtureRecorder())
    private let startNanos = DispatchTime.now().uptimeNanoseconds

    public init() {}

    /// Whether capture mode is enabled (`defaults write <domain> captureMode -bool true`).
    public static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: CaptureSink.defaultsKey)
    }

    /// Record one event from the tap thread.
    public func record(input: RecognizerInput, decision: Decision) {
        let t = Double(DispatchTime.now().uptimeNanoseconds - startNanos) / 1_000_000_000
        lock.withLock { $0.record(t: t, input: input, decision: decision) }
    }

    public var sampleCount: Int {
        lock.withLock { $0.samples.count }
    }

    /// Flush the recorded session to a fixture file. Returns the number of samples written.
    @discardableResult
    public func flush(to url: URL, name: String, osVersion: String, capturedAt: String) throws -> Int {
        let fixture = lock.withLock {
            $0.makeFixture(name: name, description: "captured live session (DERISK §2)",
                           recordedOnOS: osVersion, capturedAt: capturedAt)
        }
        try fixture.encoded().write(to: url)
        return fixture.samples.count
    }
}
