import CoreGraphics
import Foundation
import os
import SwooshCore   // Edge

/// An immutable snapshot of on-screen titlebar bands (AX global, top-left coords). A reference
/// type so the tap thread reads it with an O(1) retain — copying the whole entry array on every
/// scroll event would defeat the purpose of caching.
final class WindowSnapshot {
    struct Entry { let windowID: CGWindowID; let frame: CGRect; let band: CGRect }
    let entries: [Entry]   // frontmost-first (CGWindowList on-screen order)
    init(entries: [Entry]) { self.entries = entries }
    static let empty = WindowSnapshot(entries: [])
}

/// Layer 3 fast geometry (SPEC §6.2) with the **off-thread cache that M0 flagged as mandatory**:
/// the in-thread `CGWindowListCopyWindowInfo` call measured ~20.8 ms max and threatened the tap
/// disable ceiling. Here the snapshot is rebuilt on a background queue, and the tap thread only
/// reads the latest immutable snapshot under a momentary unfair lock (microseconds). A cache
/// miss returns `nil` ("no band" → pass) — it **never** recomputes synchronously.
public final class WindowGeometryCache {
    private let lock = OSAllocatedUnfairLock(initialState: WindowSnapshot.empty)
    private let refreshQueue = DispatchQueue(label: "swoosh.geometry", qos: .utility)
    private var timer: DispatchSourceTimer?

    /// Default titlebar band height (SPEC §6.2 / §10). Per-app derivation for tall/custom
    /// titlebars (Safari, Electron) is later work; 28 pt is the documented fallback.
    public var titlebarHeight: CGFloat

    public init(titlebarHeight: CGFloat = 28) {
        self.titlebarHeight = titlebarHeight
    }

    /// Non-blocking read for the tap thread: the titlebar band under `cursor`, or `nil`.
    public func titlebarBand(at cursor: CGPoint) -> CGRect? {
        let snapshot = lock.withLock { $0 }   // O(1): returns the immutable reference
        for entry in snapshot.entries where entry.band.contains(cursor) {
            return entry.band
        }
        return nil
    }

    /// A shared snapped edge under the cursor plus the two windows' current frames (SPEC §4.3).
    public struct DividerHit: Sendable {
        public let divider: Divider
        public let leadingFrame: CGRect
        public let trailingFrame: CGRect
    }

    /// Detect a divider under the cursor from the latest snapshot (non-blocking, fast geometry —
    /// the synchronous check on left-mouse-down, never AX, per SPEC §4.3).
    public func dividerHit(at cursor: CGPoint) -> DividerHit? {
        let snapshot = lock.withLock { $0 }
        let frames = snapshot.entries.map { WindowFrame(id: Int($0.windowID), frame: $0.frame) }
        guard let divider = DividerLocator.divider(at: cursor, among: frames),
              let lead = frames.first(where: { $0.id == divider.leading })?.frame,
              let trail = frames.first(where: { $0.id == divider.trailing })?.frame else { return nil }
        return DividerHit(divider: divider, leadingFrame: lead, trailingFrame: trail)
    }

    /// Rebuild the snapshot from `CGWindowList`. **Off the tap thread only.**
    public func refresh() {
        let snap = WindowGeometryCache.buildSnapshot(titlebarHeight: titlebarHeight)
        lock.withLock { $0 = snap }
    }

    /// Start periodic off-thread refresh. A short interval keeps geometry fresh enough that
    /// suppress-on-stale is rare; the stale-geometry failure direction is a tracked M0 risk.
    public func start(interval: TimeInterval = 0.2) {
        refreshQueue.async { [weak self] in self?.refresh() }
        let t = DispatchSource.makeTimerSource(queue: refreshQueue)
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in self?.refresh() }
        timer = t
        t.resume()
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    private static func buildSnapshot(titlebarHeight: CGFloat) -> WindowSnapshot {
        guard let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else {
            return .empty
        }
        var entries: [WindowSnapshot.Entry] = []
        for window in info {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = window[kCGWindowBounds as String],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as! CFDictionary)
            else { continue }
            let id = CGWindowID((window[kCGWindowNumber as String] as? Int) ?? 0)
            let band = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: titlebarHeight)
            entries.append(.init(windowID: id, frame: rect, band: band))
        }
        return WindowSnapshot(entries: entries)
    }
}
