// m0-bridge.h — C bridging header for the Swoosh M0 de-risk spike (THROWAWAY).
//
// Imported into the swiftc build via `-import-objc-header`. It holds the two
// things Swift cannot express directly:
//   1. The relaxed, lock-free single-writer/single-reader finger-count atomic
//      (plan KTD8) — Swift's `Synchronization.Atomic` is macOS-15+, and
//      swift-atomics would need the SwiftPM manifest KTD1 forbids, so the
//      primitive is this tiny C shim over <stdatomic.h>.
//   2. The private MultitouchSupport `MTTouch` struct, whose 96-byte size is the
//      ABI-drift tripwire (origin R17). Per-field offsets are NOT relied upon.
//
// This file is deleted with the rest of spike/m0/ once the M0 gate resolves.

#ifndef M0_BRIDGE_H
#define M0_BRIDGE_H

#include <stdint.h>
#include <stddef.h>
#include <stdatomic.h>

// --- KTD8: relaxed, lock-free finger-count hand-off ------------------------
// Swift owns the int32 storage (a heap UnsafeMutablePointer<Int32>). The
// MultitouchSupport callback thread is the sole writer; the CGEventTap callback
// is the sole reader. Only the latest count matters and no dependent payload is
// published alongside it, so `memory_order_relaxed` is sufficient — and it is
// chosen precisely to keep the realtime tap-thread read non-blocking. A lock
// here would reintroduce the tap-thread blocking the whole design avoids.
static inline void m0_atomic_store_relaxed(int32_t *ptr, int32_t value) {
    atomic_store_explicit((_Atomic int32_t *)ptr, value, memory_order_relaxed);
}
static inline int32_t m0_atomic_load_relaxed(const int32_t *ptr) {
    return atomic_load_explicit((const _Atomic int32_t *)ptr, memory_order_relaxed);
}

// --- MultitouchSupport MTTouch (private / undocumented) --------------------
// The per-field layout is reverse-engineered and NOT ABI-stable: public sources
// (mactic, asmagill, rmhsilva) disagree on the middle fields. The spike depends
// ONLY on (a) the contact callback's `numTouches` argument for the finger count
// and (b) `sizeof(MTTouch) == 96` as a drift tripwire. If the size assertion
// fails, the struct has drifted on this OS and the spike must STOP rather than
// decode garbage. Field names below are best-effort and exist only to total 96.
typedef struct { float x; float y; } MTPoint;
typedef struct { MTPoint position; MTPoint velocity; } MTVector;

typedef struct {            // total: 96 bytes (8-byte aligned via `timestamp`)
    int32_t  frame;         // +0
                            // +4 padding (for the 8-byte double below)
    double   timestamp;     // +8
    int32_t  pathIndex;     // +16
    int32_t  state;         // +20  (MTPathStage)
    int32_t  fingerID;      // +24
    int32_t  handID;        // +28
    MTVector normalized;    // +32  (16 bytes)
    float    zTotal;        // +48
    int32_t  field9;        // +52
    float    angle;         // +56
    float    majorAxis;     // +60
    float    minorAxis;     // +64
    MTVector absolute;      // +68  (16 bytes)
    int32_t  field14;       // +84
    int32_t  field15;       // +88
    float    zDensity;      // +92
} MTTouch;                  // == +96

enum {
    MTPathStageNotTracking   = 0,
    MTPathStageStartInRange  = 1,
    MTPathStageHoverInRange  = 2,
    MTPathStageMakeTouch     = 3,
    MTPathStageTouching      = 4,
    MTPathStageBreakTouch    = 5,
    MTPathStageLingerInRange = 6,
    MTPathStageOutOfRange    = 7
};

#endif /* M0_BRIDGE_H */
