import Foundation

/// Tap-callback latency instrumentation — the R9 numeric baseline the M0 RESULTS.md leaves
/// pending (it only had `max`; this adds the percentile distribution).
///
/// Single-writer by contract: the tap runloop thread appends via `record`; read the percentiles
/// only after `EventTap.disable()`, when no callback can be in flight. That keeps the hot path
/// lock-free.
public struct LatencyStats {
    private var samplesNanos: [UInt64] = []
    private let cap: Int
    public private(set) var maxNanos: UInt64 = 0
    public private(set) var count: Int = 0

    public init(capacity: Int = 200_000) {
        self.cap = capacity
        samplesNanos.reserveCapacity(min(capacity, 4096))
    }

    public mutating func record(_ nanos: UInt64) {
        count += 1
        if nanos > maxNanos { maxNanos = nanos }
        if samplesNanos.count < cap { samplesNanos.append(nanos) }
    }

    public struct Summary: Equatable, Sendable {
        public let p50, p95, p99, p999, max: Double   // milliseconds
        public let count: Int
    }

    /// Nearest-rank percentiles in milliseconds.
    public func summary() -> Summary {
        let sorted = samplesNanos.sorted()
        func pct(_ p: Double) -> Double {
            guard !sorted.isEmpty else { return 0 }
            let rank = Int((p / 100.0 * Double(sorted.count - 1)).rounded())
            return Double(sorted[min(max(rank, 0), sorted.count - 1)]) / 1_000_000.0
        }
        return Summary(p50: pct(50), p95: pct(95), p99: pct(99), p999: pct(99.9),
                       max: Double(maxNanos) / 1_000_000.0, count: count)
    }
}
