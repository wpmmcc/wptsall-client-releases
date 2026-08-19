#!/usr/bin/env bash
# Download and install from GitHub release for testing.
set -euo pipefail

VER="${WPTSALL_VERSION:-}"
PLATFORM="${1:-linux-x86_64}"
REPO="${WPTSALL_PUBLIC_REPO:-wpmmcc/wptsall-client-releases}"
PREFIX="${HOME}/.local/opt/wptsall-client"

while [ $# -gt 0 ]; do
  case "$1" in
    --platform) PLATFORM="$2"; shift 2 ;;
    --version) VER="$2"; shift 2 ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    *) shift ;;
  esac
done

[ -z "$VER" ] && { echo "ERROR: --version or WPTSALL_VERSION required" >&2; exit 1; }

TAG="v${VER}"
ASSET="wptsall-client-${VER}-${PLATFORM}.tar.gz"

echo "Installing $ASSET from $REPO $TAG → $PREFIX"
mkdir -p "$PREFIX"

gh release download "$TAG" -R "$REPO" -p "$ASSET" -D /tmp/
tar -xzf "/tmp/$ASSET" -C "$PREFIX" --strip-components=1
rm -f "/tmp/$ASSET"

echo "Installed to: $PREFIX"
echo "Binary: $PREFIX/bin/wptsall-client"
ls -la "$PREFIX/bin/"
