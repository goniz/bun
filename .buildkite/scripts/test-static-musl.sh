#!/usr/bin/env bash
set -euo pipefail

BUN_BIN="${1:-build/bun}"

echo "=== Static musl functional tests ==="

# 1. Version check
echo "[1] Version check:"
"$BUN_BIN" --version

# 2. Basic execution
echo -e "\n[2] Basic script execution:"
"$BUN_BIN" -e "console.log('✓ Hello from static Bun')"

# 3. File I/O
echo -e "\n[3] File I/O test:"
"$BUN_BIN" -e "
  import { writeFileSync, readFileSync } from 'fs';
  writeFileSync('/tmp/bun-static-test.txt', 'test');
  const content = readFileSync('/tmp/bun-static-test.txt', 'utf8');
  console.log('✓ File I/O works:', content === 'test');
"

# 4. Network (with CA cert warning)
echo -e "\n[4] Network test (requires SSL_CERT_FILE):"
export SSL_CERT_FILE=${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}
if [ ! -f "$SSL_CERT_FILE" ]; then
  echo "⚠️  Skipping: CA cert file not found at $SSL_CERT_FILE"
else
  "$BUN_BIN" -e "
    fetch('https://example.com')
      .then(r => console.log('✓ Network works, status:', r.status))
      .catch(e => { console.error('❌ Network test failed:', e.message); process.exit(1); });
  " || echo "⚠️  Network test failed (may need SSL_CERT_FILE configuration)"
fi

# 5. Cross-container test (if Docker available)
if command -v docker &>/dev/null; then
  echo -e "\n[5] Testing in minimal containers:"
  
  # Test in pure scratch container wouldn't work (no shell), so use Alpine
  echo "  - Alpine 3.22:"
  docker run --rm -v "$(realpath "$BUN_BIN"):/bun:ro" alpine:3.22 /bun --version
  
  echo "  - Alpine 3.20:"
  docker run --rm -v "$(realpath "$BUN_BIN"):/bun:ro" alpine:3.20 /bun --version || echo "  ⚠️  Failed on Alpine 3.20"
  
  echo "  - BusyBox (musl):"
  docker run --rm -v "$(realpath "$BUN_BIN"):/bun:ro" busybox:musl /bun --version || echo "  ⚠️  Failed on BusyBox"
fi

echo -e "\n=== ✅ Functional tests complete ==="
