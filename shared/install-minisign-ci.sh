#!/usr/bin/env bash
# Install minisign on GitHub-hosted runners (apt often lacks the package).
set -euo pipefail
if command -v minisign >/dev/null 2>&1; then
  exit 0
fi

VER="${MINISIGN_VERSION:-0.12}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

OS="$(uname -s)"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) SUB=x86_64 ;;
  aarch64|arm64) SUB=aarch64 ;;
  *)
    echo "unsupported arch: $ARCH" >&2
    exit 1
    ;;
esac

BIN=""
case "$OS" in
  Linux)
    curl -fsSL "https://github.com/jedisct1/minisign/releases/download/${VER}/minisign-${VER}-linux.tar.gz" \
      -o "$TMP/minisign.tgz"
    tar -xzf "$TMP/minisign.tgz" -C "$TMP"
    BIN="$TMP/minisign-linux/${SUB}/minisign"
    ;;
  Darwin)
    curl -fsSL "https://github.com/jedisct1/minisign/releases/download/${VER}/minisign-${VER}-macos.zip" \
      -o "$TMP/minisign.zip"
    unzip -q "$TMP/minisign.zip" -d "$TMP"
    BIN="$TMP/minisign"
    ;;
  *)
    echo "unsupported OS for minisign CI install: $OS" >&2
    exit 1
    ;;
esac

[ -x "$BIN" ] || { echo "minisign binary not found at $BIN" >&2; exit 1; }
if [ -w /usr/local/bin ]; then
  install -m 0755 "$BIN" /usr/local/bin/minisign
else
  sudo install -m 0755 "$BIN" /usr/local/bin/minisign
fi
minisign -V 2>/dev/null || true
