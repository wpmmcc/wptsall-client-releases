#!/usr/bin/env bash
# Public-side pack: consume a source-free kit → user release assets.
# Does NOT cargo-build. Safe for free public runners.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VER="${WPTSALL_VERSION:-}"
KIT="${KIT:-}"
OUT_DIR="${OUT_DIR:-$ROOT/dist/release-assets}"
PACK_KINDS="${WPTSALL_PACK_KINDS:-tree}"
mkdir -p "$OUT_DIR"

[ -z "$KIT" ] && { echo "ERROR: KIT env required" >&2; exit 1; }
[ -z "$VER" ] && { echo "ERROR: WPTSALL_VERSION required" >&2; exit 1; }
[ ! -f "$KIT" ] && { echo "ERROR: Kit not found: $KIT" >&2; exit 1; }

# Detect platform from kit filename
PLAT="$(basename "$KIT" .tar.gz | sed 's/kit-//')"
echo "== pack-kit-to-release ver=$VER platform=$PLAT kinds=$PACK_KINDS =="

# Extract kit
STAGE="$ROOT/dist/staging"
rm -rf "$STAGE"
mkdir -p "$STAGE"
tar -xzf "$KIT" -C "$STAGE"
TREE="$STAGE/wptsall-client"

kind_has() { echo ",${PACK_KINDS}," | grep -q ",$1,"; }

# Tree tarball (always)
if kind_has tree; then
  ASSET="$OUT_DIR/wptsall-client-${VER}-${PLAT}.tar.gz"
  tar -czf "$ASSET" -C "$STAGE" wptsall-client
  echo "Created: $ASSET"
fi

# Portable ZIP (Windows)
if kind_has portable; then
  ASSET="$OUT_DIR/wptsall-client-${VER}-${PLAT}-portable.zip"
  (cd "$STAGE" && zip -qr "$ASSET" wptsall-client)
  echo "Created: $ASSET"
fi

# DEB
if kind_has deb && command -v dpkg-deb >/dev/null 2>&1; then
  DEB_ROOT="$STAGE/deb-root"
  mkdir -p "$DEB_ROOT/DEBIAN"
  mkdir -p "$DEB_ROOT/opt/wptsall-client"
  mkdir -p "$DEB_ROOT/usr/share/applications"
  cp -r "$TREE"/* "$DEB_ROOT/opt/wptsall-client/"

  ARCH_DEB="amd64"
  echo "$PLAT" | grep -q aarch64 && ARCH_DEB="arm64"

  cat > "$DEB_ROOT/DEBIAN/control" <<EOF
Package: wptsall-client
Version: ${VER}
Section: utils
Priority: optional
Architecture: ${ARCH_DEB}
Maintainer: WPMM <info@wpmm.cc>
Description: WPTSALL Translation Client
 Desktop client for WordPress multilingual translation.
EOF

  cat > "$DEB_ROOT/usr/share/applications/wptsall-client.desktop" <<EOF
[Desktop Entry]
Name=WPTSALL Client
Exec=/opt/wptsall-client/bin/wptsall-client
Type=Application
Categories=Utility;
EOF

  ASSET="$OUT_DIR/wptsall-client_${VER}_${ARCH_DEB}.deb"
  dpkg-deb --build "$DEB_ROOT" "$ASSET"
  echo "Created: $ASSET"
fi

# AppImage
if kind_has appimage && command -v appimagetool >/dev/null 2>&1; then
  APPDIR="$STAGE/wptsall-client.AppDir"
  mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share"
  cp -r "$TREE"/* "$APPDIR/usr/"
  cp "$TREE/bin/wptsall-client" "$APPDIR/usr/bin/" 2>/dev/null || true
  cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/bash
exec "$(dirname "$0")/usr/bin/wptsall-client" "$@"
EOF
  chmod +x "$APPDIR/AppRun"
  cat > "$APPDIR/wptsall-client.desktop" <<EOF
[Desktop Entry]
Name=WPTSALL Client
Exec=wptsall-client
Type=Application
Categories=Utility;
EOF
  # Placeholder icon
  touch "$APPDIR/wptsall-client.png"

  ASSET="$OUT_DIR/wptsall-client-${VER}-${PLAT}.AppImage"
  ARCH_AI="x86_64"
  echo "$PLAT" | grep -q aarch64 && ARCH_AI="aarch64"
  ARCH="$ARCH_AI" appimagetool "$APPDIR" "$ASSET" 2>/dev/null || echo "AppImage: tool failed (non-fatal)"
  [ -f "$ASSET" ] && echo "Created: $ASSET"
fi

# NSIS (Windows) — requires makensis
if kind_has nsis && command -v makensis >/dev/null 2>&1; then
  echo "NSIS packaging not yet implemented in this script."
fi

# DMG (macOS) — requires hdiutil
if kind_has dmg && command -v hdiutil >/dev/null 2>&1; then
  APP_NAME="WPTSALL Client"
  APP_DIR="$STAGE/${APP_NAME}.app"
  mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
  cp "$TREE/bin/wptsall-client" "$APP_DIR/Contents/MacOS/"
  cp -r "$TREE/ui" "$APP_DIR/Contents/Resources/" 2>/dev/null || true
  cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>cc.wpmm.wptsall-client</string>
  <key>CFBundleVersion</key><string>${VER}</string>
  <key>CFBundleExecutable</key><string>wptsall-client</string>
</dict>
</plist>
EOF

  ASSET="$OUT_DIR/wptsall-client-${VER}-${PLAT}.dmg"
  hdiutil create -volname "$APP_NAME" -srcfolder "$APP_DIR" -ov -format UDZO "$ASSET"
  echo "Created: $ASSET"
fi

# SHA256 sums
cd "$OUT_DIR"
sha256sum wptsall-client-* *.deb 2>/dev/null > RELEASE-SHA256SUMS.txt || true
echo "Done. Assets in: $OUT_DIR"
