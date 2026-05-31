import Foundation

/// Layer 2 (SPEC §7). Abstracts finger-count so Layers 1/3/4 are agnostic to whether the
/// private `MultitouchSupport` path or the public `NSEvent` Plan B is active. `contactCount`
/// is read on the tap thread, so it must be a cheap, non-blocking atomic read.
public protocol FingerCountSource: AnyObject {
    /// The current number of active contacts (atomic read; never blocks).
    var contactCount: Int { get }
    /// Begin streaming contact frames. Consumes input — may require Input Monitoring (KTD6, open).
    func start() throws
    /// Stop the stream and release resources.
    func stop()
}

public enum FingerCountError: Error, CustomStringConvertible {
    case frameworkUnavailable(path: String)
    case missingSymbols([String])

    public var description: String {
        switch self {
        case .frameworkUnavailable(let p): return "could not dlopen \(p)"
        case .missingSymbols(let s):       return "MultitouchSupport symbols missing: \(s.joined(separator: ", "))"
        }
    }
}

/// Plan B (SPEC §7, DERISK §5): the public `NSEvent` touch path. Specced as the safety net
/// behind the same protocol; **not implemented in M1** — it is promoted from fallback to
/// default only if a DERISK §5 trigger fires. Until then it reports zero so the live daemon
/// degrades to "never our gesture" rather than misfiring.
public final class NSEventFingerCount: FingerCountSource {
    public init() {}
    public var contactCount: Int { 0 }
    public func start() throws {}
    public func stop() {}
}
