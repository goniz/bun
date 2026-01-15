#!/usr/bin/env bash
set -euo pipefail

BUN_BIN="${1:-build/bun}"

echo "=== Verifying static musl build: $BUN_BIN ==="

# 1. File type
echo -e "\n[1] File type check:"
FILE_OUTPUT=$(file "$BUN_BIN")
echo "$FILE_OUTPUT"
if ! echo "$FILE_OUTPUT" | grep -q "statically linked"; then
  echo "❌ ERROR: Binary is not statically linked"
  exit 1
fi
echo "✓ Binary is statically linked"

# 2. LDD check
echo -e "\n[2] LDD check:"
LDD_OUTPUT=$(ldd "$BUN_BIN" 2>&1 || true)
echo "$LDD_OUTPUT"
if echo "$LDD_OUTPUT" | grep -qE "(not a dynamic|statically linked|not dynamic)"; then
  echo "✓ No dynamic dependencies"
else
  echo "❌ ERROR: Binary has dynamic dependencies"
  exit 1
fi

# 3. Readelf - no NEEDED entries
echo -e "\n[3] Dynamic section (NEEDED) check:"
if readelf -d "$BUN_BIN" 2>/dev/null | grep -q NEEDED; then
  echo "❌ ERROR: Found dynamic library dependencies:"
  readelf -d "$BUN_BIN" | grep NEEDED
  exit 1
else
  echo "✓ No NEEDED dynamic libraries"
fi

# 4. No interpreter
echo -e "\n[4] Interpreter check:"
INTERP=$(readelf -l "$BUN_BIN" 2>/dev/null | grep interpreter || true)
if [ -n "$INTERP" ]; then
  echo "❌ ERROR: Dynamic interpreter found:"
  echo "$INTERP"
  exit 1
else
  echo "✓ No dynamic linker/interpreter"
fi

# 5. Alpine scanelf (if available)
if command -v scanelf &>/dev/null; then
  echo -e "\n[5] Scanelf check:"
  scanelf -n "$BUN_BIN" || true
fi

# 6. Check for GLIBC symbols (should be none)
echo -e "\n[6] GLIBC symbol check:"
if strings "$BUN_BIN" | grep -q "GLIBC_"; then
  echo "⚠️  WARNING: Found GLIBC version symbols (should use musl)"
  strings "$BUN_BIN" | grep "GLIBC_" | head -5
fi

# 7. Binary size
echo -e "\n[7] Binary size:"
ls -lh "$BUN_BIN" | awk '{print "Size:", $5}'

# 8. Smoke test
echo -e "\n[8] Smoke test:"
if ! "$BUN_BIN" --version >/dev/null 2>&1; then
  echo "❌ ERROR: Binary doesn't execute"
  exit 1
fi
VERSION=$("$BUN_BIN" --version)
echo "✓ Binary executes: $VERSION"

echo -e "\n=== ✅ All static verification checks passed ==="
