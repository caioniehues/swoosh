#!/bin/sh
# Capability-manifest assertion (STRATEGY §5). Fails if the code uses any private/undocumented
# surface not declared in CAPABILITIES.md. Run by CI (.github/workflows/ci.yml) and locally:
#   sh scripts/check-capabilities.sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/CAPABILITIES.md"
SRC="$ROOT/Sources"
fail=0

if [ ! -f "$MANIFEST" ]; then
  echo "FAIL: CAPABILITIES.md not found at $MANIFEST"
  exit 1
fi

# 1. Every private-framework symbol resolved via dlsym, i.e. sym("NAME"), confined to MultitouchClient.
symbols=$(grep -rhoE 'sym\("[A-Za-z0-9_]+"\)' "$SRC" 2>/dev/null \
          | sed -E 's/sym\("([A-Za-z0-9_]+)"\)/\1/' | sort -u)

# 2. Known-private AX attributes used anywhere in the code.
ax_attrs=$(grep -rhoE '"AX(FullScreen|EnhancedUserInterface)"' "$SRC" 2>/dev/null \
           | tr -d '"' | sort -u)

for token in $symbols $ax_attrs; do
  if ! grep -q "$token" "$MANIFEST"; then
    echo "UNDECLARED: '$token' is used in Sources/ but is not declared in CAPABILITIES.md"
    fail=1
  fi
done

if [ "$fail" -eq 0 ]; then
  echo "capability check OK — every private surface in the code is declared in CAPABILITIES.md"
  echo "  symbols:  $(echo "$symbols" | tr '\n' ' ')"
  echo "  ax attrs: $(echo "$ax_attrs" | tr '\n' ' ')"
fi
exit $fail
