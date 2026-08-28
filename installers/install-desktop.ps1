<#
.SYNOPSIS
  WPTSALL Desktop installer for Windows.

.DESCRIPTION
  Downloads a minisign-signed kit-desktop-windows-* tarball and extracts it to
  LocalAppData. Unsigned installs are fail-closed by default; -AllowUnsigned is
  a local/debug-only escape hatch.

.PARAMETER Version
  Release version, for example 2.1.0.

.PARAMETER Platform
  Optional platform override: windows-x86_64 or windows-aarch64.

.PARAMETER InstallPath
  Default: $env:LOCALAPPDATA\wptsall-desktop.

.PARAMETER DownloadBase
  Optional base URL used by CI/local HTTP tests.

.PARAMETER AllowUnsigned
  Skip minisign verification (debug only).
#>
[CmdletBinding()]
param(
    [string]$Version = "",
    [string]$Platform = "",
    [string]$InstallPath = "",
    [string]$DownloadBase = "",
    [switch]$NoPath,
    [switch]$NoStartup,
    [switch]$AllowUnsigned
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo = if ($env:WPTSALL_PUBLIC_REPO) { $env:WPTSALL_PUBLIC_REPO } else { "wpmmcc/wptsall-client-releases" }
$MinisignPubkey = if ($env:WPTSALL_MINISIGN_PUBKEY) { $env:WPTSALL_MINISIGN_PUBKEY } else { "RWR7lrdabZEEywfWEfrRJXIyP5h+LHEabOA8JFiNJ3vGLpNtppyabHfP" }
if (-not $Version -and $env:WPTSALL_VERSION) { $Version = $env:WPTSALL_VERSION }
if (-not $DownloadBase -and $env:WPTSALL_DOWNLOAD_BASE) { $DownloadBase = $env:WPTSALL_DOWNLOAD_BASE }
if ($env:WPTSALL_ALLOW_UNSIGNED -eq "1") { $AllowUnsigned = $true }

function Write-Step { param([string]$Msg) Write-Host "  $Msg" -ForegroundColor Cyan }
function Write-Ok { param([string]$Msg) Write-Host "  $Msg" -ForegroundColor Green }
function Write-Err { param([string]$Msg) Write-Host "  ERROR: $Msg" -ForegroundColor Red }

function Resolve-WptsallPlatform {
    if ($Platform) { return $Platform }
    if (-not [Environment]::Is64BitOperatingSystem) {
        Write-Err "32-bit Windows is not supported."
        exit 1
    }
    $arch = "x86_64"
    try {
        $cpuArch = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1).Architecture
        if ($cpuArch -eq 12) { $arch = "aarch64" }
    } catch {
        if ($env:PROCESSOR_ARCHITECTURE -match "ARM64") { $arch = "aarch64" }
    }
    return "windows-$arch"
}

function Invoke-WptsallDownload {
    param([string]$Uri, [string]$OutFile, [switch]$Optional)
    try {
        Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
        return $true
    } catch {
        if ($Optional) { return $false }
        throw
    }
}

Write-Host ""
Write-Host "  WPTSALL Desktop Installer (Windows)" -ForegroundColor White
Write-Host ""

if (-not $Version) {
    Write-Err "Version is required. Pass -Version or set WPTSALL_VERSION."
    exit 1
}

$ResolvedPlatform = Resolve-WptsallPlatform
if ($ResolvedPlatform -notin @("windows-x86_64", "windows-aarch64")) {
    Write-Err "Unsupported Windows platform: $ResolvedPlatform"
    exit 1
}
Write-Step "Platform: $ResolvedPlatform"
Write-Step "Version: $Version"

if (-not $InstallPath) {
    $InstallPath = Join-Path $env:LOCALAPPDATA "wptsall-desktop"
}
Write-Step "Install path: $InstallPath"

$Asset = "kit-desktop-$ResolvedPlatform.tar.gz"
$Base = if ($DownloadBase) { $DownloadBase.TrimEnd("/") } else { "https://github.com/$Repo/releases/download/kits-desktop-v$Version" }
$Url = "$Base/$Asset"
$SigUrl = "$Url.minisig"
$SumsUrl = "$Base/RELEASE-SHA256SUMS-desktop.txt"

$TempDir = Join-Path $env:TEMP "wptsall-desktop-install-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
$TempFile = Join-Path $TempDir $Asset
$TempSig = Join-Path $TempDir "$Asset.minisig"
$TempSums = Join-Path $TempDir "RELEASE-SHA256SUMS-desktop.txt"

try {
    Write-Step "Downloading $Asset..."
    $oldProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WptsallDownload -Uri $Url -OutFile $TempFile | Out-Null
    $sigDownloaded = Invoke-WptsallDownload -Uri $SigUrl -OutFile $TempSig -Optional
    $sumsDownloaded = Invoke-WptsallDownload -Uri $SumsUrl -OutFile $TempSums -Optional
    $ProgressPreference = $oldProgress

    if (-not $AllowUnsigned) {
        $minisign = Get-Command minisign -ErrorAction SilentlyContinue
        if (-not $minisign) {
            Write-Err "minisign is required to verify Desktop artifacts. Use -AllowUnsigned only for local debug."
            exit 1
        }
        if (-not $sigDownloaded -or -not (Test-Path $TempSig)) {
            Write-Err "missing .minisig — refusing unsigned install"
            exit 1
        }
        Write-Step "Verifying minisign..."
        & minisign -Vm $TempFile -P $MinisignPubkey -x $TempSig
        if ($LASTEXITCODE -ne 0) {
            Write-Err "minisign verification failed"
            exit 1
        }
        Write-Ok "Minisign signature verified."
    } else {
        Write-Step "AllowUnsigned: skipping minisign"
    }

    if ($sumsDownloaded -and (Test-Path $TempSums)) {
        Write-Step "Verifying checksum..."
        $expectedLine = Get-Content $TempSums | Where-Object { $_ -match [regex]::Escape($Asset) } | Select-Object -First 1
        if ($expectedLine) {
            $expected = ($expectedLine -split '\s+')[0].ToLowerInvariant()
            $actual = (Get-FileHash -Path $TempFile -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actual -ne $expected) {
                Write-Err "Checksum mismatch. Expected $expected got $actual"
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
        exit 1
    }

    $Root = Join-Path $ExtractDir "wptsall-client"
    if (-not (Test-Path $Root)) {
        $firstDir = Get-ChildItem -Path $ExtractDir -Directory | Select-Object -First 1
        if ($firstDir) { $Root = $firstDir.FullName }
    }
    if (-not (Test-Path $Root)) {
        Write-Err "kit root directory missing"
        exit 1
    }

    Write-Step "Installing to $InstallPath..."
    if (Test-Path $InstallPath) { Remove-Item -Recurse -Force $InstallPath }
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    Copy-Item -Path (Join-Path $Root '*') -Destination $InstallPath -Recurse -Force

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
        $ShortcutPath = Join-Path $StartupDir "WPTSALL Desktop.lnk"
        try {
            $WshShell = New-Object -ComObject WScript.Shell
            $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
            $Shortcut.TargetPath = $Exe
            $Shortcut.WorkingDirectory = $InstallPath
            $Shortcut.Description = "WPTSALL Desktop Translation Client"
            $Shortcut.Save()
            Write-Step "Startup shortcut created."
        } catch {
            Write-Step "Could not create startup shortcut (non-fatal)."
        }
    }

    Write-Host ""
    Write-Ok "Installation complete!"
    Write-Host "  Binary: $Exe"
    Write-Host ""
} finally {
    Remove-Item -Recurse -Force $TempDir -ErrorAction SilentlyContinue
}
