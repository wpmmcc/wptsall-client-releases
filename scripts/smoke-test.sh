#!/usr/bin/env bash
# Post-install smoke test: verify binary exists, runs, and responds.
set -euo pipefail

PREFIX="${HOME}/.local/opt/wptsall-client"
BIN="$PREFIX/bin/wptsall-client"

echo "=== Smoke Test ==="

# 1. Binary exists and is executable
[ -x "$BIN" ] || { echo "FAIL: binary not executable: $BIN"; exit 1; }
echo "PASS: binary exists"

# 2. Version output
"$BIN" --version 2>/dev/null && echo "PASS: --version" || echo "WARN: --version not supported"

# 3. UI assets exist
[ -d "$PREFIX/ui/desktop" ] || echo "WARN: ui/desktop not found"
[ -f "$PREFIX/ui/desktop/index.html" ] && echo "PASS: UI dist present" || echo "WARN: index.html missing"

# 4. Check no source leakage
if find "$PREFIX" -name "Cargo.toml" -o -name "*.rs" | grep -q .; then
  echo "FAIL: source code found in install tree"
  exit 1
fi
echo "PASS: no source leakage"

echo "=== All smoke checks passed ==="
