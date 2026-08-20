#!/usr/bin/env bash
# Post-install smoke test for WebUI (kit or installer prefix).
set -euo pipefail

PREFIX="${1:-${HOME}/.local/opt/wptsall-client}"
BIN="$PREFIX/bin/wptsall-client"
BIN_EXE="$PREFIX/bin/wptsall-client.exe"
[ -x "$BIN" ] || [ -f "$BIN_EXE" ] || { echo "FAIL: binary missing under $PREFIX/bin"; exit 1; }
echo "PASS: binary exists"

# Do not exec --version: this binary starts the WebUI if the flag is unknown.
if [ -x "$BIN" ]; then
  file "$BIN" | grep -qiE 'ELF|Mach-O' && echo "PASS: native binary" || echo "WARN: unexpected file type"
  head -c 4 "$BIN" | od -An -tx1 | grep -qi '7f 45 4c 46' && echo "PASS: ELF magic" || true
fi

if find "$PREFIX" \( -name "Cargo.toml" -o -name "*.rs" \) | grep -q .; then
  echo "FAIL: source code found in install tree"
  exit 1
fi
echo "PASS: no source leakage"

[ -f "$PREFIX/VERSION" ] && echo "PASS: VERSION=$(cat "$PREFIX/VERSION")" || echo "WARN: no VERSION file"
[ -f "$PREFIX/HARDENING.txt" ] && echo "PASS: HARDENING.txt present" || echo "WARN: no HARDENING.txt"

echo "=== WebUI smoke checks passed ($PREFIX) ==="
