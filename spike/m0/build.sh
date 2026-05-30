#!/bin/sh
# Throwaway build for the Swoosh M0 de-risk spike (plan KTD1 / KTD5).
#
# swiftc-direct — deliberately NO SwiftPM / Package.swift, so the spike never
# masquerades as the real project skeleton. Produces an ad-hoc-signed bare
# arm64 binary with `disable-library-validation` and NO sandbox so it can
# dlopen the private MultitouchSupport framework. Output lands in build/
# (gitignored); this whole directory is deleted once the M0 gate resolves.
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$DIR/../../build"
OUT="$OUT_DIR/m0spike"
mkdir -p "$OUT_DIR"

echo "compiling (swiftc, arm64, with C bridging header)..."
swiftc -O \
  -import-objc-header "$DIR/m0-bridge.h" \
  "$DIR"/*.swift \
  -framework CoreFoundation \
  -framework IOKit \
  -framework ApplicationServices \
  -o "$OUT"

echo "ad-hoc signing with throwaway entitlements (hardened runtime)..."
codesign --sign - --force --options runtime \
  --entitlements "$DIR/m0.entitlements" \
  "$OUT"

echo "built + signed: $OUT"
echo "run: $OUT scaffold"
