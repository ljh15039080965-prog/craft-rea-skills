<#
.SYNOPSIS
  Install the Craft Anything + REA skill/MCP pair into Claude Code and Codex.

.DESCRIPTION
  Step 1 (REA):
    npx -y rea-agents@<ver> setup --client <client> --yes
    Writes the MCP registration and installs the reverse-engineer-anything skill.

  Step 2 (Craft Anything):
    Downloads the upstream release for this platform when craft-anything-cli is
    not already installed, then runs:
    craft-anything-cli setup --client <client> --yes

  A dead local npm proxy in ~/.npmrc is bypassed with --proxy=false.

.PARAMETER Client
  all (default) | claude_code | codex | claude_desktop | vscode | opencode | copilot_cli

.PARAMETER CraftAnythingDir
  Where to unpack craft-anything-cli. Default: %USERPROFILE%\Tools\craft-anything

.PARAMETER ReaVersion
  Pinned rea-agents version. Default: 6.5.0

.PARAMETER CraftVersion
  Pinned craft-anything release. Default: 0.6.1

.EXAMPLE
  pwsh -File scripts/install.ps1
  pwsh -File scripts/install.ps1 -Client codex
#>
[CmdletBinding()]
param(
  [string]$Client = 'all',
  [string]$CraftAnythingDir = (Join-Path $env:USERPROFILE 'Tools\craft-anything'),
  [string]$ReaVersion = '6.5.0',
  [string]$CraftVersion = '0.6.1',
  [switch]$SkipRea,
  [switch]$SkipCraft
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Step($msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }
function Write-Ok($msg) { Write-Host "   [ok]   $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "   [skip] $msg" -ForegroundColor DarkGray }
function Write-Warn2($msg) { Write-Host "   [warn] $msg" -ForegroundColor Yellow }

# Some shells export a proxy that is not listening; npm/npx then fail with ECONNREFUSED.
$env:HTTP_PROXY = ''
$env:HTTPS_PROXY = ''
$env:ALL_PROXY = ''
$env:NO_PROXY = '*'

$clients = if ($Client -eq 'all') { @('claude_code', 'codex') } else { @($Client) }

Write-Step 'Environment'
$nodeOk = $false
try { $nodeVersion = (node -v) 2>$null; $nodeOk = $true } catch { }
if ($nodeOk) { Write-Ok "node $nodeVersion" } else { Write-Warn2 'node not found - REA needs Node.js >= 22.19'; exit 1 }
try { $npmVersion = (npm -v) 2>$null; Write-Ok "npm $npmVersion" } catch { Write-Warn2 'npm not found' }
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } elseif ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
Write-Ok "windows-$arch"

# ---------------------------------------------------------------- REA
if (-not $SkipRea) {
  Write-Step "REA $ReaVersion"
  foreach ($c in $clients) {
    try {
      $out = npx --proxy=false --https-proxy=false -y "rea-agents@$ReaVersion" setup --client $c --yes 2>&1 | Out-String
      if ($out -match 'status:\s*ready' -or $out -match 'configured') { Write-Ok "$c configured" }
      else { Write-Warn2 "$c: unexpected output`n$out" }
    } catch {
      Write-Warn2 "$c failed: $($_.Exception.Message)"
    }
  }
} else { Write-Skip 'REA (skipped)' }

# ------------------------------------------------------- Craft Anything
if (-not $SkipCraft) {
  Write-Step "Craft Anything $CraftVersion"

  $cli = $null
  $existing = Get-Command craft-anything-cli -ErrorAction SilentlyContinue
  if ($existing) { $cli = $existing.Source }

  if (-not $cli) {
    $found = Get-ChildItem -Path $CraftAnythingDir -Filter 'craft-anything-cli.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $cli = $found.FullName }
  }

  if (-not $cli) {
    $zipName = "craft-anything-$CraftVersion-windows-$arch-portable.zip"
    $url = "https://github.com/storytold/craft-anything/releases/download/v$CraftVersion/$zipName"
    $zip = Join-Path $env:TEMP $zipName
    Write-Host "   downloading $zipName (about 70 MB)"
    try {
      curl.exe -L --noproxy "*" --fail --silent --show-error -o $zip $url
    } catch {
      Write-Warn2 "download failed: $url"; $zip = $null
    }
    if ($zip -and (Test-Path $zip)) {
      New-Item -ItemType Directory -Force -Path $CraftAnythingDir | Out-Null
      Expand-Archive -Path $zip -DestinationPath $CraftAnythingDir -Force
      $found = Get-ChildItem -Path $CraftAnythingDir -Filter 'craft-anything-cli.exe' -Recurse | Select-Object -First 1
      if ($found) { $cli = $found.FullName }
    }
  }

  if (-not $cli) {
    Write-Warn2 'craft-anything-cli not available; install it manually from https://github.com/storytold/craft-anything/releases'
  } else {
    Write-Ok "cli: $cli"
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $cliDir = Split-Path $cli -Parent
    if ($userPath -notlike "*$cliDir*") {
      [Environment]::SetEnvironmentVariable('Path', "$userPath;$cliDir", 'User')
      $env:Path = "$env:Path;$cliDir"
      Write-Ok "added $cliDir to user PATH (new terminals only)"
    }

    foreach ($c in $clients) {
      try {
        $out = & $cli setup --client $c --yes --format text 2>&1 | Out-String
        if ($out -match 'configured') { Write-Ok "$c configured" } else { Write-Warn2 "$c: $out" }
      } catch {
        Write-Warn2 "$c failed: $($_.Exception.Message)"
      }
    }

    Write-Step 'Self test'
    try { & $cli doctor --format text 2>&1 | Out-String | Write-Host } catch { Write-Warn2 "doctor failed: $($_.Exception.Message)" }
  }
} else { Write-Skip 'Craft Anything (skipped)' }

Write-Host ''
Write-Host 'Restart Claude Code and Codex to load the new MCP servers and skills.' -ForegroundColor Cyan
Write-Host 'Verify with:  pwsh -File scripts/verify.ps1' -ForegroundColor Cyan
