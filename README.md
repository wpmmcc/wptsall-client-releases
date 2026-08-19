# WPTSALL Client Releases

Public packaging, installation, and testing for the WPTSALL Translation Desktop Client.

## What this repo does

- Consumes pre-built **kits** (source-free binary packages) from prerelease tags
- Packs them into user-facing installation formats (deb, AppImage, exe, dmg, tar.gz)
- Runs installation and smoke tests on GitHub free runners
- Publishes final release assets

## Supported Platforms

| Platform | Formats | Runner |
|----------|---------|--------|
| Linux x86_64 | tar.gz, deb, AppImage | ubuntu-22.04 |
| Linux aarch64 | tar.gz, deb, AppImage | ubuntu-24.04-arm |
| Windows x86_64 | tar.gz, NSIS setup, portable zip | windows-latest |
| macOS aarch64 | tar.gz, dmg | macos-latest |

## Installation

Download the latest release for your platform from [Releases](../../releases).

### Linux (deb)
```bash
sudo apt install -y ./wptsall-client_*.deb
```

### Linux (AppImage)
```bash
chmod +x wptsall-client-*.AppImage
./wptsall-client-*.AppImage
```

### Linux (tar.gz)
```bash
tar -xzf wptsall-client-*-linux-x86_64.tar.gz
cd wptsall-client && ./bin/wptsall-client
```

### Windows
Run `wptsall-client-*-setup.exe` or extract the portable zip.

### macOS
Open the `.dmg` and drag to Applications.

## Architecture

```
[Private monorepo] → make-kit.sh → kit-<os>-<arch>.tar.gz
    ↓ upload to kits-v* prerelease
[This repo] → pack-kit-to-release.sh → user packages
    ↓ publish v* release
[Users] → download + install
```

This repo does NOT contain source code for the client binary.
It only contains packaging scripts, workflows, and documentation.
