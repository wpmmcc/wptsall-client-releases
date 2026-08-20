#!/usr/bin/env bash
# Install minisign on GitHub-hosted runners (apt often lacks the package).
set -euo pipefail
if command -v minisign >/dev/null 2>&1; then
  exit 0
fi
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) MS_ARCH=linux ;;
  aarch64|arm64) MS_ARCH=linux-aarch64 ;;
  *)
    echo "unsupported arch for minisign CI install: $ARCH" >&2
    exit 1
    ;;
esac
VER="${MINISIGN_VERSION:-0.11}"
TMP="$(mktemp -d)"
curl -fsSL "https://github.com/jedisct1/minisign/releases/download/${VER}/minisign-${VER}-${MS_ARCH}.tar.gz" \
  -o "$TMP/minisign.tgz"
tar -xzf "$TMP/minisign.tgz" -C "$TMP"
BIN="$(find "$TMP" -name minisign -type f | head -1)"
[ -n "$BIN" ] || { echo "minisign binary not found in tarball" >&2; exit 1; }
if [ -w /usr/local/bin ]; then
  install -m 0755 "$BIN" /usr/local/bin/minisign
else
  sudo install -m 0755 "$BIN" /usr/local/bin/minisign
fi
rm -rf "$TMP"
minisign -V || minisign -h | head -1
