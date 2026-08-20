<#
.SYNOPSIS
  WPTSALL Client WebUI installer for Windows.

.DESCRIPTION
  Downloads the minisign-signed kit (no Authenticode). Extracts to LocalAppData.

.PARAMETER Version
  Specific version. If omitted, uses the newest kits-webui-v* GitHub release.

.PARAMETER InstallPath
  Default: $env:LOCALAPPDATA\wptsall-client

.PARAMETER DownloadBase
  Override kit URL prefix (local/CI). Same as env WPTSALL_DOWNLOAD_BASE.

.PARAMETER AllowUnsigned
  Skip minisign (debug only).
#>
[CmdletBinding()]
param(
    [string]$Version = "",
    [string]$InstallPath = "",
    [string]$DownloadBase = "",
    [switch]$NoPath,
    [switch]$NoStartup,
    [switch]$AllowUnsigned
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo = if ($env:WPTSALL_PUBLIC_REPO) { $env:WPTSALL_PUBLIC_REPO } else { "wpmmcc/wptsall-client-releases" }
$MinisignPubkey = "RWR7lrdabZEEywfWEfrRJXIyP5h+LHEabOA8JFiNJ3vGLpNtppyabHfP"
if (-not $DownloadBase -and $env:WPTSALL_DOWNLOAD_BASE) { $DownloadBase = $env:WPTSALL_DOWNLOAD_BASE }
if ($env:WPTSALL_ALLOW_UNSIGNED -eq "1") { $AllowUnsigned = $true }

function Write-Step { param([string]$Msg) Write-Host "  $Msg" -ForegroundColor Cyan }
function Write-Ok { param([string]$Msg) Write-Host "  $Msg" -ForegroundColor Green }
function Write-Err { param([string]$Msg) Write-Host "  ERROR: $Msg" -ForegroundColor Red }

Write-Host ""
Write-Host "  WPTSALL Client Installer (Windows WebUI)" -ForegroundColor White
Write-Host ""

$Arch = if ([Environment]::Is64BitOperatingSystem) {
    $cpu = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue).Architecture
    if ($cpu -eq 12) { "aarch64" } else { "x86_64" }
} else {
    Write-Err "32-bit Windows is not supported."
    exit 1
}
$Platform = "windows-$Arch"
Write-Step "Detected platform: $Platform"

if (-not $Version) {
    Write-Step "Fetching latest kits-webui release..."
    $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases" -UseBasicParsing
    foreach ($r in $releases) {
        if ($r.tag_name -match '^kits-webui-v(.+)$') {
            $Version = $Matches[1]
            break
        }
    }
}
if (-not $Version) {
    Write-Err "Could not determine version. Pass -Version."
    exit 1
}
Write-Step "Version: $Version"

if (-not $InstallPath) {
    $InstallPath = Join-Path $env:LOCALAPPDATA "wptsall-client"
}
Write-Step "Install path: $InstallPath"

$Asset = "kit-webui-$Platform.tar.gz"
if ($DownloadBase) {
    $Base = $DownloadBase.TrimEnd("/")
} else {
    $Base = "https://github.com/$Repo/releases/download/kits-webui-v$Version"
}
$Url = "$Base/$Asset"
$SigUrl = "$Url.minisig"
$SumsUrl = "$Base/RELEASE-SHA256SUMS-webui.txt"

$TempDir = Join-Path $env:TEMP "wptsall-install-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
$TempFile = Join-Path $TempDir $Asset
$TempSig = Join-Path $TempDir "$Asset.minisig"
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

try { Invoke-WebRequest -Uri $SigUrl -OutFile $TempSig -UseBasicParsing } catch { $TempSig = "" }
try { Invoke-WebRequest -Uri $SumsUrl -OutFile $TempSums -UseBasicParsing } catch { $TempSums = "" }
$ProgressPreference = $oldProgress

if (-not $AllowUnsigned) {
    $minisign = Get-Command minisign -ErrorAction SilentlyContinue
    if (-not $minisign) {
        Write-Err "minisign is required. Install it, or pass -AllowUnsigned (debug only)."
        Remove-Item -Recurse -Force $TempDir
        exit 1
    }
    if (-not $TempSig -or -not (Test-Path $TempSig)) {
        Write-Err "missing .minisig — refusing unsigned install"
        Remove-Item -Recurse -Force $TempDir
        exit 1
    }
    Write-Step "Verifying minisign..."
    & minisign -Vm $TempFile -P $MinisignPubkey -x $TempSig
    if ($LASTEXITCODE -ne 0) {
        Write-Err "minisign verification failed"
        Remove-Item -Recurse -Force $TempDir
        exit 1
    }
    Write-Ok "Minisign signature verified."
} else {
    Write-Step "AllowUnsigned: skipping minisign"
}

if ($TempSums -and (Test-Path $TempSums)) {
    Write-Step "Verifying checksum..."
    $expectedLine = Get-Content $TempSums | Where-Object { $_ -match [regex]::Escape($Asset) } | Select-Object -First 1
    if ($expectedLine) {
        $expected = ($expectedLine -split '\s+')[0].ToLower()
        $actual = (Get-FileHash -Path $TempFile -Algorithm SHA256).Hash.ToLower()
        if ($actual -ne $expected) {
            Write-Err "Checksum mismatch. Expected $expected got $actual"
            Remove-Item -Recurse -Force $TempDir
            exit 1
        }
        Write-Ok "Checksum verified."
    }
}

Write-Step "Extracting..."
$ExtractDir = Join-Path $TempDir "extracted"
New-Item -ItemType Directory -Path $ExtractDir -Force | Out-Null
tar -xzf $TempFile -C $ExtractDir
if ($LASTEXITCODE -ne 0) {
    Write-Err "Extraction failed (need Windows 10 1803+ tar)."
    Remove-Item -Recurse -Force $TempDir
    exit 1
}

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

$BinPath = Join-Path $InstallPath "bin"
$Exe = Join-Path $BinPath "wptsall-client.exe"
if (-not (Test-Path $Exe)) {
    Write-Err "wptsall-client.exe missing after extract"
    exit 1
}

if (-not $NoPath) {
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($currentPath -notlike "*$BinPath*") {
        Write-Step "Adding $BinPath to user PATH..."
        [Environment]::SetEnvironmentVariable("PATH", "$BinPath;$currentPath", "User")
        $env:PATH = "$BinPath;$env:PATH"
        Write-Ok "PATH updated (restart shell for effect)."
    }
}

if (-not $NoStartup) {
    $StartupDir = [Environment]::GetFolderPath("Startup")
    $ShortcutPath = Join-Path $StartupDir "WPTSALL Client.lnk"
    try {
        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
        $Shortcut.TargetPath = $Exe
        $Shortcut.WorkingDirectory = $InstallPath
        $Shortcut.Description = "WPTSALL Translation Client"
        $Shortcut.Save()
        Write-Step "Startup shortcut created."
    } catch {
        Write-Step "Could not create startup shortcut (non-fatal)."
    }
}

Remove-Item -Recurse -Force $TempDir -ErrorAction SilentlyContinue

Write-Host ""
Write-Ok "Installation complete!"
Write-Host "  Binary: $Exe"
Write-Host "  WebUI:  http://127.0.0.1:8977"
Write-Host ""
