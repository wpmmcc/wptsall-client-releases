<#
.SYNOPSIS
  WPTSALL Client WebUI installer for Windows.

.DESCRIPTION
  Downloads and installs the WPTSALL Translation Client (WebUI mode) on Windows.
  Detects architecture (x86_64 / arm64), downloads from GitHub Release,
  verifies SHA256 checksum, and installs to LocalAppData.

.PARAMETER Version
  Specific version to install. If omitted, installs latest.

.PARAMETER InstallPath
  Installation directory. Default: $env:LOCALAPPDATA\wptsall-client

.PARAMETER NoPath
  Skip adding install directory to user PATH.

.EXAMPLE
  # One-liner (PowerShell 5.1+):
  irm https://raw.githubusercontent.com/wpmmcc/wptsall-client-releases/main/install.ps1 | iex

  # With specific version:
  .\install.ps1 -Version 2.1.0
#>
[CmdletBinding()]
param(
    [string]$Version = "",
    [string]$InstallPath = "",
    [switch]$NoPath,
    [switch]$NoStartup
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo = "wpmmcc/wptsall-client-releases"

function Write-Step { param([string]$Msg) Write-Host "  $Msg" -ForegroundColor Cyan }
function Write-Ok { param([string]$Msg) Write-Host "  $Msg" -ForegroundColor Green }
function Write-Err { param([string]$Msg) Write-Host "  ERROR: $Msg" -ForegroundColor Red }

Write-Host ""
Write-Host "  WPTSALL Client Installer (Windows)" -ForegroundColor White
Write-Host "  ====================================" -ForegroundColor DarkGray
Write-Host ""

# ── Detect architecture ──────────────────────────────────────────────────────
$Arch = if ([Environment]::Is64BitOperatingSystem) {
    $cpu = (Get-CimInstance Win32_Processor).Architecture
    # 12 = ARM64, 9 = x64
    if ($cpu -eq 12) { "aarch64" } else { "x86_64" }
} else {
    Write-Err "32-bit Windows is not supported."
    exit 1
}
$Platform = "windows-$Arch"
Write-Step "Detected platform: $Platform"

# ── Resolve version ──────────────────────────────────────────────────────────
if (-not $Version) {
    Write-Step "Fetching latest release..."
    $releaseInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -UseBasicParsing
    $Version = $releaseInfo.tag_name -replace '^v', ''
}
if (-not $Version) {
    Write-Err "Could not determine version."
    exit 1
}
Write-Step "Version: $Version"

# ── Set install path ─────────────────────────────────────────────────────────
if (-not $InstallPath) {
    $InstallPath = Join-Path $env:LOCALAPPDATA "wptsall-client"
}
Write-Step "Install path: $InstallPath"

# ── Download ─────────────────────────────────────────────────────────────────
$Asset = "wptsall-client-webui-$Version-$Platform.tar.gz"
$Url = "https://github.com/$Repo/releases/download/v$Version/$Asset"
$SumsUrl = "https://github.com/$Repo/releases/download/v$Version/RELEASE-SHA256SUMS.txt"

$TempDir = Join-Path $env:TEMP "wptsall-install-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
$TempFile = Join-Path $TempDir $Asset
$TempSums = Join-Path $TempDir "SHA256SUMS.txt"

Write-Step "Downloading $Asset..."
$oldProgress = $ProgressPreference
$ProgressPreference = 'SilentlyContinue'
try {
    Invoke-WebRequest -Uri $Url -OutFile $TempFile -UseBasicParsing
} catch {
    Write-Err "Download failed: $_"
    Remove-Item -Recurse -Force $TempDir -ErrorAction SilentlyContinue
    exit 1
}

# Download checksums (optional)
try {
    Invoke-WebRequest -Uri $SumsUrl -OutFile $TempSums -UseBasicParsing
} catch {
    $TempSums = ""
}
$ProgressPreference = $oldProgress

# ── Verify SHA256 ────────────────────────────────────────────────────────────
if ($TempSums -and (Test-Path $TempSums)) {
    Write-Step "Verifying checksum..."
    $sumsContent = Get-Content $TempSums
    $expectedLine = $sumsContent | Where-Object { $_ -match $Asset }
    if ($expectedLine) {
        $expected = ($expectedLine -split '\s+')[0].ToLower()
        $actual = (Get-FileHash -Path $TempFile -Algorithm SHA256).Hash.ToLower()
        if ($actual -ne $expected) {
            Write-Err "Checksum mismatch!"
            Write-Err "  Expected: $expected"
            Write-Err "  Got:      $actual"
            Remove-Item -Recurse -Force $TempDir
            exit 1
        }
        Write-Ok "Checksum verified."
    } else {
        Write-Step "Asset not in SHA256SUMS, skipping verification."
    }
} else {
    Write-Step "SHA256SUMS not available, skipping verification."
}

# ── Extract ──────────────────────────────────────────────────────────────────
Write-Step "Extracting..."
$ExtractDir = Join-Path $TempDir "extracted"
New-Item -ItemType Directory -Path $ExtractDir -Force | Out-Null

# Use tar (available on Windows 10+)
tar -xzf $TempFile -C $ExtractDir 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Err "Extraction failed. Ensure Windows 10 1803+ (tar available)."
    Remove-Item -Recurse -Force $TempDir
    exit 1
}

# ── Install ──────────────────────────────────────────────────────────────────
Write-Step "Installing to $InstallPath..."
if (Test-Path $InstallPath) {
    Remove-Item -Recurse -Force $InstallPath
}
$SourceDir = Get-ChildItem -Path $ExtractDir -Directory | Select-Object -First 1
if ($SourceDir) {
    Move-Item -Path $SourceDir.FullName -Destination $InstallPath -Force
} else {
    Move-Item -Path $ExtractDir -Destination $InstallPath -Force
}

# ── Add to PATH ──────────────────────────────────────────────────────────────
$BinPath = Join-Path $InstallPath "bin"
if (-not $NoPath) {
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($currentPath -notlike "*$BinPath*") {
        Write-Step "Adding $BinPath to user PATH..."
        [Environment]::SetEnvironmentVariable("PATH", "$BinPath;$currentPath", "User")
        $env:PATH = "$BinPath;$env:PATH"
        Write-Ok "PATH updated (restart shell for effect)."
    } else {
        Write-Step "Already in PATH."
    }
}

# ── Create startup shortcut (optional) ───────────────────────────────────────
if (-not $NoStartup) {
    $StartupDir = [Environment]::GetFolderPath("Startup")
    $ShortcutPath = Join-Path $StartupDir "WPTSALL Client.lnk"
    try {
        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
        $Shortcut.TargetPath = Join-Path $BinPath "wptsall-client.exe"
        $Shortcut.WorkingDirectory = $InstallPath
        $Shortcut.Description = "WPTSALL Translation Client"
        $Shortcut.Save()
        Write-Step "Startup shortcut created."
    } catch {
        Write-Step "Could not create startup shortcut (non-fatal)."
    }
}

# ── Cleanup ──────────────────────────────────────────────────────────────────
Remove-Item -Recurse -Force $TempDir -ErrorAction SilentlyContinue

Write-Host ""
Write-Ok "Installation complete!"
Write-Host ""
Write-Host "  Binary: $BinPath\wptsall-client.exe" -ForegroundColor White
Write-Host "  Start:  wptsall-client" -ForegroundColor White
Write-Host "  WebUI:  http://127.0.0.1:8977" -ForegroundColor White
Write-Host ""
