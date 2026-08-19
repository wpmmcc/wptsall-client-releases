#!/bin/sh
# WPTSALL Client WebUI — one-line installer for Linux and macOS.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/wpmmcc/wptsall-client-releases/main/install.sh | sh
#   curl -fsSL ... | sh -s -- --version 2.1.0
#   bash install.sh --version 2.1.0 --prefix /opt/wptsall
#
# Supports: linux-x86_64, linux-aarch64, darwin-x86_64, darwin-aarch64
set -eu

REPO="wpmmcc/wptsall-client-releases"
VERSION=""
PREFIX="${HOME}/.local/opt/wptsall-client"
BIN_LINK="${HOME}/.local/bin"
CREATE_SERVICE=1

# Parse args
while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    --no-service) CREATE_SERVICE=0; shift ;;
    -h|--help)
      echo "Usage: install.sh [--version VER] [--prefix DIR] [--no-service]"
      exit 0 ;;
    *) shift ;;
  esac
done

# ── Detect platform ──────────────────────────────────────────────────────────
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

OS="$(detect_os)"
ARCH="$(detect_arch)"
PLATFORM="${OS}-${ARCH}"
echo "Detected platform: $PLATFORM"

# ── Resolve version ──────────────────────────────────────────────────────────
if [ -z "$VERSION" ]; then
  echo "Fetching latest release version..."
  if command -v curl >/dev/null 2>&1; then
    VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | \
      grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
  elif command -v wget >/dev/null 2>&1; then
    VERSION=$(wget -qO- "https://api.github.com/repos/${REPO}/releases/latest" | \
      grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
  else
    echo "ERROR: curl or wget required" >&2
    exit 1
  fi
fi

if [ -z "$VERSION" ]; then
  echo "ERROR: could not determine version" >&2
  exit 1
fi
echo "Installing version: $VERSION"

# ── Download ─────────────────────────────────────────────────────────────────
ASSET="wptsall-client-webui-${VERSION}-${PLATFORM}.tar.gz"
URL="https://github.com/${REPO}/releases/download/v${VERSION}/${ASSET}"
SUMS_URL="https://github.com/${REPO}/releases/download/v${VERSION}/RELEASE-SHA256SUMS.txt"

TMPDIR="${TMPDIR:-/tmp}"
TMP_FILE="$TMPDIR/$ASSET"
TMP_SUMS="$TMPDIR/wptsall-sha256sums.txt"

echo "Downloading $ASSET..."
if command -v curl >/dev/null 2>&1; then
  curl -fSL "$URL" -o "$TMP_FILE"
  curl -fsSL "$SUMS_URL" -o "$TMP_SUMS" 2>/dev/null || true
elif command -v wget >/dev/null 2>&1; then
  wget -q "$URL" -O "$TMP_FILE"
  wget -q "$SUMS_URL" -O "$TMP_SUMS" 2>/dev/null || true
fi

# ── Verify SHA256 ────────────────────────────────────────────────────────────
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
      echo "ERROR: checksum mismatch!" >&2
      echo "  Expected: $EXPECTED" >&2
      echo "  Got:      $ACTUAL" >&2
      rm -f "$TMP_FILE" "$TMP_SUMS"
      exit 1
    fi
    echo "Checksum verified."
  else
    echo "WARN: asset not found in SHA256SUMS, skipping verification"
  fi
else
  echo "WARN: SHA256SUMS not available, skipping verification"
fi

# ── Install ──────────────────────────────────────────────────────────────────
echo "Installing to $PREFIX..."
mkdir -p "$PREFIX"
tar -xzf "$TMP_FILE" -C "$PREFIX" --strip-components=1
chmod +x "$PREFIX/bin/"*

# Symlink to PATH
mkdir -p "$BIN_LINK"
ln -sf "$PREFIX/bin/wptsall-client" "$BIN_LINK/wptsall-client"

# ── Create systemd user service (Linux only) ─────────────────────────────────
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

# ── Create launchd plist (macOS only) ────────────────────────────────────────
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
  echo "  Load: launchctl load $PLIST_DIR/cc.wpmm.wptsall-client.plist"
fi

# ── Cleanup ──────────────────────────────────────────────────────────────────
rm -f "$TMP_FILE" "$TMP_SUMS"

echo ""
echo "Installation complete!"
echo "  Binary: $PREFIX/bin/wptsall-client"
echo "  Symlink: $BIN_LINK/wptsall-client"
echo ""
echo "Make sure $BIN_LINK is in your PATH:"
echo "  export PATH=\"$BIN_LINK:\$PATH\""
echo ""
echo "Start the client:"
echo "  wptsall-client"
echo "  # Then open http://127.0.0.1:8977 in your browser"
