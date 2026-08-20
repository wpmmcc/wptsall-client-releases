#!/usr/bin/env bash
# Public-side WebUI pack: consume a source-free signed kit → user tarball.
# Does NOT cargo-build. Does NOT re-sign (minisign stays on the original kit).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_CLIENT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$INSTALL_CLIENT"

VER="${WPTSALL_VERSION:-}"
KIT="${KIT:-}"
OUT_DIR="${OUT_DIR:-$INSTALL_CLIENT/dist/release-assets}"
mkdir -p "$OUT_DIR"

[ -z "$KIT" ] && { echo "ERROR: KIT env required" >&2; exit 1; }
[ -z "$VER" ] && { echo "ERROR: WPTSALL_VERSION required" >&2; exit 1; }
[ -f "$KIT" ] || { echo "ERROR: Kit not found: $KIT" >&2; exit 1; }

PLAT="$(basename "$KIT" .tar.gz | sed 's/^kit-webui-//;s/^kit-//')"
echo "== pack webui kit ver=$VER platform=$PLAT =="

STAGE="$INSTALL_CLIENT/dist/staging-webui"
rm -rf "$STAGE"
mkdir -p "$STAGE"
tar -xzf "$KIT" -C "$STAGE"

ROOT_DIR=""
if [ -d "$STAGE/wptsall-client-webui" ]; then
  ROOT_DIR="wptsall-client-webui"
elif [ -d "$STAGE/wptsall-client" ]; then
  ROOT_DIR="wptsall-client"
else
  echo "ERROR: kit has neither wptsall-client-webui/ nor wptsall-client/" >&2
  tar -tzf "$KIT" | head
  exit 1
fi

BIN="$STAGE/$ROOT_DIR/bin/wptsall-client"
BIN_EXE="$STAGE/$ROOT_DIR/bin/wptsall-client.exe"
if [ ! -f "$BIN" ] && [ ! -f "$BIN_EXE" ]; then
  echo "ERROR: no wptsall-client binary in kit" >&2
  exit 1
fi

ASSET="$OUT_DIR/wptsall-client-webui-${VER}-${PLAT}.tar.gz"
tar -czf "$ASSET" -C "$STAGE" "$ROOT_DIR"
echo "Created: $ASSET"

cd "$OUT_DIR"
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$(basename "$ASSET")" > "SHA256SUMS-${PLAT}.txt"
else
  shasum -a 256 "$(basename "$ASSET")" > "SHA256SUMS-${PLAT}.txt"
fi
echo "Done. Assets in: $OUT_DIR"
