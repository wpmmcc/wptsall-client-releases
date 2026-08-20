#!/bin/sh
# WPTSALL Client WebUI — one-line installer for Linux and macOS.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/wpmmcc/wptsall-client-releases/main/install.sh | sh
#   curl -fsSL ... | sh -s -- --version 2.1.0
#   bash install.sh --version 2.1.0 --prefix /opt/wptsall
#
# Downloads the **signed kit** (minisign). No Apple/Microsoft OS certificate.
#
# Env:
#   WPTSALL_PUBLIC_REPO          default wpmmcc/wptsall-client-releases
#   WPTSALL_DOWNLOAD_BASE        if set, fetch kit from this URL prefix (local/CI tests)
#   WPTSALL_ALLOW_UNSIGNED=1     skip minisign (debug only)
set -eu

MINISIGN_PUBKEY="RWR7lrdabZEEywfWEfrRJXIyP5h+LHEabOA8JFiNJ3vGLpNtppyabHfP"

REPO="${WPTSALL_PUBLIC_REPO:-wpmmcc/wptsall-client-releases}"
VERSION=""
PREFIX="${HOME}/.local/opt/wptsall-client"
BIN_LINK="${HOME}/.local/bin"
CREATE_SERVICE=1
ALLOW_UNSIGNED="${WPTSALL_ALLOW_UNSIGNED:-0}"
CREATE_LINK=1

while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    --no-service) CREATE_SERVICE=0; shift ;;
    --no-link) CREATE_LINK=0; shift ;;
    --allow-unsigned) ALLOW_UNSIGNED=1; shift ;;
    -h|--help)
      echo "Usage: install.sh [--version VER] [--prefix DIR] [--no-service] [--no-link] [--allow-unsigned]"
      exit 0 ;;
    *) shift ;;
  esac
done

detect_os() {
  case "$(uname -s)" in
    Linux*) echo "linux" ;;
    Darwin*) echo "darwin" ;;
    *) echo "unsupported"; exit 1 ;;
  esac
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "x86_64" ;;
    aarch64|arm64) echo "aarch64" ;;
    *) echo "unsupported"; exit 1 ;;
  esac
}

fetch() {
  _url="$1"
  _out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fSL "$_url" -o "$_out"
  elif command -v wget >/dev/null 2>&1; then
    wget -q "$_url" -O "$_out"
  else
    echo "ERROR: curl or wget required" >&2
    exit 1
  fi
}

fetch_text() {
  _url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$_url"
  else
    wget -qO- "$_url"
  fi
}

OS="$(detect_os)"
ARCH="$(detect_arch)"
PLATFORM="${OS}-${ARCH}"
echo "Detected platform: $PLATFORM"

if [ -z "$VERSION" ]; then
  echo "Fetching latest WebUI version..."
  VERSION=$(fetch_text "https://api.github.com/repos/${REPO}/releases" | \
    sed -n 's/.*"tag_name": *"kits-webui-v\([^"]*\)".*/\1/p' | head -1 || true)
fi

if [ -z "$VERSION" ]; then
  echo "ERROR: could not determine version (pass --version)" >&2
  exit 1
fi
echo "Installing version: $VERSION"

ASSET="kit-webui-${PLATFORM}.tar.gz"
if [ -n "${WPTSALL_DOWNLOAD_BASE:-}" ]; then
  BASE="${WPTSALL_DOWNLOAD_BASE%/}"
else
  BASE="https://github.com/${REPO}/releases/download/kits-webui-v${VERSION}"
fi
URL="${BASE}/${ASSET}"
SUMS_URL="${BASE}/RELEASE-SHA256SUMS-webui.txt"
SIG_URL="${URL}.minisig"
SUMS_SIG_URL="${SUMS_URL}.minisig"

TMPDIR="${TMPDIR:-/tmp}"
TMP_FILE="$TMPDIR/$ASSET"
TMP_SUMS="$TMPDIR/wptsall-sha256sums-webui.txt"
SIG_FILE="${TMP_FILE}.minisig"

echo "Downloading $ASSET..."
fetch "$URL" "$TMP_FILE"
fetch "$SIG_URL" "$SIG_FILE" || true
fetch "$SUMS_URL" "$TMP_SUMS" || true

if [ "$ALLOW_UNSIGNED" != "1" ]; then
  if ! command -v minisign >/dev/null 2>&1; then
    echo "ERROR: minisign is required to verify the kit. Install it, or pass --allow-unsigned (debug only)." >&2
    echo "  Debian/Ubuntu: sudo apt install minisign" >&2
    echo "  macOS: brew install minisign" >&2
    rm -f "$TMP_FILE" "$SIG_FILE" "$TMP_SUMS"
    exit 1
  fi
  if [ ! -s "$SIG_FILE" ]; then
    echo "ERROR: missing $SIG_URL — refusing unsigned install" >&2
    rm -f "$TMP_FILE" "$TMP_SUMS"
    exit 1
  fi
  echo "Verifying minisign signature..."
  if ! minisign -Vm "$TMP_FILE" -P "$MINISIGN_PUBKEY" -x "$SIG_FILE"; then
    echo "ERROR: minisign verification failed" >&2
    rm -f "$TMP_FILE" "$SIG_FILE" "$TMP_SUMS"
    exit 1
  fi
  echo "Minisign signature verified."
else
  echo "WARN: --allow-unsigned / WPTSALL_ALLOW_UNSIGNED=1, skipping minisign"
fi

if [ -f "$TMP_SUMS" ] && [ -s "$TMP_SUMS" ]; then
  echo "Verifying checksum..."
  EXPECTED=$(grep "$ASSET" "$TMP_SUMS" | awk '{print $1}')
  if [ -n "$EXPECTED" ]; then
    if command -v sha256sum >/dev/null 2>&1; then
      ACTUAL=$(sha256sum "$TMP_FILE" | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
      ACTUAL=$(shasum -a 256 "$TMP_FILE" | awk '{print $1}')
    else
      ACTUAL=""
    fi
    if [ -n "$ACTUAL" ] && [ "$ACTUAL" != "$EXPECTED" ]; then
      echo "ERROR: checksum mismatch" >&2
      echo "  Expected: $EXPECTED" >&2
      echo "  Got:      $ACTUAL" >&2
      rm -f "$TMP_FILE" "$TMP_SUMS" "$SIG_FILE"
      exit 1
    fi
    echo "Checksum verified."
  fi
fi

echo "Installing to $PREFIX..."
mkdir -p "$PREFIX"
# kit top-level is wptsall-client-webui/
tar -xzf "$TMP_FILE" -C "$PREFIX" --strip-components=1
chmod +x "$PREFIX/bin/"* 2>/dev/null || true

BIN_NAME="wptsall-client"
[ -f "$PREFIX/bin/wptsall-client.exe" ] && BIN_NAME="wptsall-client.exe"
if [ ! -f "$PREFIX/bin/$BIN_NAME" ]; then
  echo "ERROR: binary missing after extract" >&2
  exit 1
fi

mkdir -p "$BIN_LINK"
if [ "$CREATE_LINK" = "1" ]; then
  ln -sf "$PREFIX/bin/wptsall-client" "$BIN_LINK/wptsall-client"
fi

if [ "$OS" = "linux" ] && [ "$CREATE_SERVICE" = "1" ]; then
  SVCDIR="${HOME}/.config/systemd/user"
  mkdir -p "$SVCDIR"
  cat > "$SVCDIR/wptsall-client.service" <<EOF
[Unit]
Description=WPTSALL Translation Client (WebUI)
After=network-online.target

[Service]
Type=simple
ExecStart=${PREFIX}/bin/wptsall-client
Restart=on-failure
RestartSec=5
Environment=WPTSALL_DATA_DIR=${HOME}/.local/share/wptsall-client

[Install]
WantedBy=default.target
EOF
  echo "Systemd service created: $SVCDIR/wptsall-client.service"
  echo "  Enable: systemctl --user enable --now wptsall-client"
fi

if [ "$OS" = "darwin" ] && [ "$CREATE_SERVICE" = "1" ]; then
  PLIST_DIR="${HOME}/Library/LaunchAgents"
  mkdir -p "$PLIST_DIR"
  cat > "$PLIST_DIR/cc.wpmm.wptsall-client.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>cc.wpmm.wptsall-client</string>
  <key>ProgramArguments</key>
  <array><string>${PREFIX}/bin/wptsall-client</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>${HOME}/.local/share/wptsall-client/stdout.log</string>
  <key>StandardErrorPath</key><string>${HOME}/.local/share/wptsall-client/stderr.log</string>
</dict>
</plist>
EOF
  echo "LaunchAgent created: $PLIST_DIR/cc.wpmm.wptsall-client.plist"
fi

rm -f "$TMP_FILE" "$TMP_SUMS" "$SIG_FILE" 2>/dev/null || true

echo ""
echo "Installation complete!"
echo "  Binary: $PREFIX/bin/wptsall-client"
if [ "$CREATE_LINK" = "1" ]; then
  echo "  Symlink: $BIN_LINK/wptsall-client"
  echo ""
  echo "Make sure $BIN_LINK is in your PATH:"
  echo "  export PATH=\"$BIN_LINK:\$PATH\""
fi
echo ""
echo "Start the client:"
echo "  $PREFIX/bin/wptsall-client"
echo "  # Then open http://127.0.0.1:8977 in your browser"
