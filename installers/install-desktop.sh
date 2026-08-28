#!/usr/bin/env bash
# Install Desktop client from signed kit-desktop-* (preferred) or packed release tree.
#
# Preferred (kit line, same trust as WebUI):
#   WPTSALL_DOWNLOAD_BASE=... bash install-desktop.sh --version 2.1.0
#   → kits-desktop-v{ver}/kit-desktop-{platform}.tar.gz + minisig
#
# Fallback (after runner pack):
#   bash install-desktop.sh --version 2.1.0 --from-packed
#   → v{ver}/wptsall-client-{ver}-{platform}.tar.gz
#
# Unsigned packed artifacts are intentionally a debug-only escape hatch:
#   bash install-desktop.sh --version 2.1.0 --from-packed --allow-unsigned
set -euo pipefail

INSTALL_CLIENT="$(cd "$(dirname "$0")/.." && pwd)"
VER="${WPTSALL_VERSION:-}"
PLATFORM=""
PREFIX="${HOME}/.local/opt/wptsall-client"
REPO="${WPTSALL_PUBLIC_REPO:-wpmmcc/wptsall-client-releases}"
FROM_PACKED=0
NO_LINK=0
DOWNLOAD_BASE="${WPTSALL_DOWNLOAD_BASE:-}"
ALLOW_UNSIGNED="${WPTSALL_ALLOW_UNSIGNED:-0}"
# Keep the public verification key in the installer so a public-repo checkout
# can verify kits without depending on this private monorepo's config.env.
DEFAULT_MINISIGN_PUBKEY="RWR7lrdabZEEywfWEfrRJXIyP5h+LHEabOA8JFiNJ3vGLpNtppyabHfP"

detect_platform() {
  local os arch
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  case "$arch" in x86_64|amd64) arch=x86_64 ;; aarch64|arm64) arch=aarch64 ;; esac
  case "$os" in msys*|mingw*|cygwin*) os=windows ;; darwin) os=darwin ;; linux*) os=linux ;; esac
  echo "${os}-${arch}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --platform) PLATFORM="$2"; shift 2 ;;
    --version) VER="$2"; shift 2 ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --from-packed) FROM_PACKED=1; shift ;;
    --no-link) NO_LINK=1; shift ;;
    --allow-unsigned) ALLOW_UNSIGNED=1; shift ;;
    --help|-h)
      sed -n '2,14p' "$0"
      exit 0
      ;;
    *) shift ;;
  esac
done

[ -n "$VER" ] || { echo "ERROR: --version or WPTSALL_VERSION required" >&2; exit 1; }
[ -n "$PLATFORM" ] || PLATFORM="$(detect_platform)"

verify_artifact() {
  local artifact="$1"
  local signature="${artifact}.minisig"
  local pub="${WPTSALL_MINISIGN_PUBKEY:-$DEFAULT_MINISIGN_PUBKEY}"

  if [ "$ALLOW_UNSIGNED" = "1" ]; then
    echo "WARN: unsigned install explicitly allowed (--allow-unsigned/WPTSALL_ALLOW_UNSIGNED=1)" >&2
    return 0
  fi
  if ! command -v minisign >/dev/null 2>&1; then
    echo "ERROR: minisign is required to verify Desktop artifacts. Use --allow-unsigned only for local debug." >&2
    return 1
  fi
  if [ -z "$pub" ] || [ ! -s "$signature" ]; then
    echo "ERROR: signed artifact or minisign public key is missing; refusing fail-open install." >&2
    echo "       Expected signature: $signature" >&2
    echo "       For local debug only, pass --allow-unsigned." >&2
    return 1
  fi
  minisign -Vm "$artifact" -P "$pub" -x "$signature"
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ "$FROM_PACKED" = "1" ]; then
  TAG="v${VER}"
  ASSET="wptsall-client-${VER}-${PLATFORM}.tar.gz"
  echo "Installing packed $ASSET from $REPO $TAG → $PREFIX"
  if [ -n "$DOWNLOAD_BASE" ]; then
    curl -fsSL "$DOWNLOAD_BASE/$ASSET" -o "$TMP/$ASSET"
    curl -fsSL "$DOWNLOAD_BASE/${ASSET}.minisig" -o "$TMP/${ASSET}.minisig" 2>/dev/null || true
  else
    gh release download "$TAG" -R "$REPO" -p "$ASSET" -D "$TMP"
    gh release download "$TAG" -R "$REPO" -p "${ASSET}.minisig" -D "$TMP" 2>/dev/null || true
  fi
  verify_artifact "$TMP/$ASSET"
  mkdir -p "$PREFIX"
  tar -xzf "$TMP/$ASSET" -C "$PREFIX" --strip-components=1
else
  TAG="kits-desktop-v${VER}"
  ASSET="kit-desktop-${PLATFORM}.tar.gz"
  echo "Installing kit $ASSET from $REPO $TAG → $PREFIX"
  if [ -n "$DOWNLOAD_BASE" ]; then
    curl -fsSL "${DOWNLOAD_BASE%/}/$ASSET" -o "$TMP/$ASSET"
    curl -fsSL "${DOWNLOAD_BASE%/}/${ASSET}.minisig" -o "$TMP/${ASSET}.minisig" 2>/dev/null || true
  else
    gh release download "$TAG" -R "$REPO" -p "$ASSET" -p "${ASSET}.minisig" -D "$TMP" || \
      gh release download "$TAG" -R "$REPO" -p "$ASSET" -D "$TMP"
  fi

  PUB="${WPTSALL_MINISIGN_PUBKEY:-$DEFAULT_MINISIGN_PUBKEY}"
  if [ -z "$PUB" ] && [ -f "$INSTALL_CLIENT/security/config.env" ]; then
    # shellcheck source=/dev/null
    source "$INSTALL_CLIENT/security/config.env" || true
    PUB="${WPTSALL_MINISIGN_PUBKEY:-}"
  fi
  WPTSALL_MINISIGN_PUBKEY="$PUB" verify_artifact "$TMP/$ASSET"

  mkdir -p "$PREFIX" "$TMP/extract"
  tar -xzf "$TMP/$ASSET" -C "$TMP/extract"
  if [ -d "$TMP/extract/wptsall-client" ]; then
    rm -rf "$PREFIX"
    mkdir -p "$PREFIX"
    cp -a "$TMP/extract/wptsall-client/." "$PREFIX/"
  else
    echo "ERROR: kit root wptsall-client missing" >&2
    exit 1
  fi
fi

chmod +x "$PREFIX/bin/wptsall-client" 2>/dev/null || true
if [ "$NO_LINK" != "1" ]; then
  mkdir -p "${HOME}/.local/bin"
  ln -sfn "$PREFIX/bin/wptsall-client" "${HOME}/.local/bin/wptsall-client" 2>/dev/null || true
fi

echo "Installed to: $PREFIX"
echo "Binary: $PREFIX/bin/wptsall-client"
[ -f "$PREFIX/VERSION-BINARY" ] && echo "VERSION-BINARY=$(cat "$PREFIX/VERSION-BINARY")"
[ -f "$PREFIX/VERSION-WEBUI" ] && echo "VERSION-WEBUI=$(cat "$PREFIX/VERSION-WEBUI")"
ls -la "$PREFIX/bin/" "$PREFIX/ui/desktop/" 2>/dev/null || ls -la "$PREFIX/bin/"
