#!/bin/sh
# U6 — Cross-OS matrix runner for the Swoosh M0 de-risk spike (THROWAWAY).
#
# Run this on EACH target OS — macOS 14 (Sonoma), 15 (Sequoia), 26 (Tahoe) —
# ideally with an external Magic Trackpad attached. It builds the spike and runs
# every probe, collecting a per-OS JSONL decision log under build/results/.
# Aggregate those logs into RESULTS.md (the durable go/no-go artifact).
#
# The TCC-gated probes do nothing until you grant the binary the permissions and
# set the matching env flag. First run grants, then:
#
#   M0_LISTEN=1 M0_TAP=1 M0_AX=1 M0_HAPTIC=1 sh spike/m0/run-matrix.sh
#
#   M0_LISTEN=1  fingers  -> start the contact stream (Input Monitoring; touch 2 fingers)
#   M0_TAP=1     suppress -> install the active tap   (Accessibility; pan a titlebar)
#   M0_AX=1      axact    -> AX move/resize self-test  (Accessibility; cursor over a window)
#   M0_HAPTIC=1  haptics  -> actuate the trackpad      (feel for the tap)
#   M0_DWELL_MS=<n> suppress -> dwell-sweep to MEASURE the disable threshold
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
OSVER="$(sw_vers -productVersion)"
RESDIR="$DIR/../../build/results"
mkdir -p "$RESDIR"
LOG="$RESDIR/m0-macos-$OSVER.jsonl"
: > "$LOG"

sh "$DIR/build.sh"
BIN="$DIR/../../build/m0spike"

echo "=== M0 matrix on macOS $OSVER ==="
echo "log: $LOG"
echo "grant Accessibility + Input Monitoring to: $BIN"
echo

run() {
  echo "--- probe: $1 ---"
  env M0_LOG="$LOG" "$BIN" "$1" || echo "(probe $1 exited non-zero — recorded in the log)"
  echo
}

run scaffold   # U1 — build/load/struct/atomic/TCC (no grant needed)
run fingers    # U2 — devices; M0_LISTEN=1 for live finger counts (Input Monitoring)
run suppress   # U3 — dry; M0_TAP=1 for the active tap (Accessibility)
run axact      # U4 — dry; M0_AX=1 for the AX move/resize (Accessibility)
run haptics    # U5 — devices; M0_HAPTIC=1 to actuate (feel for the tap)

echo "=== done on macOS $OSVER. Fold $RESDIR/*.jsonl into spike/m0/RESULTS.md ==="
