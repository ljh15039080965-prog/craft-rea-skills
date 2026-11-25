<#
.SYNOPSIS
  Verify that the Craft Anything and REA registrations are aligned and that both
  MCP servers actually answer a JSON-RPC initialize.

.DESCRIPTION
  Read-only. Writes a temporary probe script under %TEMP% and removes it after.

.PARAMETER Client
  Client id used for the REA doctor scope. Default: claude_code

.PARAMETER SkipHandshake
  Only check registrations, do not spawn the servers.

.EXAMPLE
  pwsh -File scripts/verify.ps1
  pwsh -File scripts/verify.ps1 -Client codex
#>
[CmdletBinding()]
param(
  [string]$Client = 'claude_code',
  [string]$ReaVersion = '6.5.0',
  [switch]$SkipHandshake
)

$ErrorActionPreference = 'Continue'
$env:HTTP_PROXY = ''
$env:HTTPS_PROXY = ''
$env:ALL_PROXY = ''
$env:NO_PROXY = '*'

function Write-Section($m) { Write-Host "`n== $m" -ForegroundColor Cyan }
$fail = 0

Write-Section "REA registration ($Client)"
try {
  $json = npx --proxy=false --https-proxy=false -y "rea-agents@$ReaVersion" doctor --client $Client --json 2>$null | Out-String
  $start = $json.IndexOf('{')
  if ($start -lt 0) { Write-Host '   no JSON returned' -ForegroundColor Red; $fail++ }
  else {
    $doc = ($json.Substring($start) | ConvertFrom-Json)
    $skill = $doc.identity.skill
    Write-Host ("   skill: v{0} tools={1} state={2}" -f $skill.installed_version, $skill.installed_tool_count, $skill.state)
    foreach ($r in $doc.identity.registrations) {
      if ($r.client -in @($Client, 'codex')) {
        $color = if ($r.state -eq 'aligned') { 'Green' } else { 'Yellow' }
        Write-Host ("   {0}: {1}  ({2})" -f $r.client, $r.state, $r.config_path) -ForegroundColor $color
        if ($r.state -ne 'aligned') { $fail++ }
      }
    }
  }
} catch { Write-Host "   REA doctor failed: $($_.Exception.Message)" -ForegroundColor Red; $fail++ }

Write-Section 'Craft Anything registration'
$cli = $null
$existing = Get-Command craft-anything-cli -ErrorAction SilentlyContinue
if ($existing) { $cli = $existing.Source }
if (-not $cli) {
  $found = Get-ChildItem -Path (Join-Path $env:USERPROFILE 'Tools\craft-anything') -Filter 'craft-anything-cli.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($found) { $cli = $found.FullName }
}
if (-not $cli) { Write-Host '   craft-anything-cli not found' -ForegroundColor Yellow; $fail++ }
else {
  Write-Host "   cli: $cli"
  $doc = (& $cli doctor --format json 2>$null | Out-String)
  $start = $doc.IndexOf('{')
  if ($start -ge 0) {
    $d = ($doc.Substring($start) | ConvertFrom-Json)
    foreach ($c in $d.checks) {
      if ($c.name -like 'registration:*' -or $c.name -like 'mcp:*') {
        $color = if ($c.status -eq 'ok') { 'Green' } elseif ($c.status -eq 'info') { 'DarkGray' } else { 'Yellow' }
        Write-Host ("   {0}: {1}" -f $c.name, $c.status) -ForegroundColor $color
      }
    }
    Write-Host ("   healthy: {0}" -f $d.healthy)
    if (-not $d.healthy) { $fail++ }
  } else { Write-Host '   doctor returned no JSON' -ForegroundColor Red; $fail++ }
}

if (-not $SkipHandshake) {
  Write-Section 'MCP handshake'
  $probe = Join-Path $env:TEMP ('craft-rea-probe-' + [guid]::NewGuid().ToString('N') + '.mjs')
  @'
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

function probe(command, args, timeoutMs) {
  return new Promise((resolve) => {
    const p = spawn(command, args, { stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true });
    let buf = ''; let done = false; const pending = new Map();
    const finish = (state, extra = {}) => { if (done) return; done = true; try { p.kill(); } catch {} resolve({ state, ...extra }); };
    const timer = setTimeout(() => finish('timeout'), timeoutMs);
    p.stdout.on('data', (d) => {
      buf += d.toString('utf8');
      let i;
      while ((i = buf.indexOf('\n')) >= 0) {
        const line = buf.slice(0, i).trim(); buf = buf.slice(i + 1);
        if (!line.startsWith('{')) continue;
        try { const m = JSON.parse(line); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } } catch {}
      }
    });
    p.stderr.on('data', () => {});
    p.on('error', (e) => finish('spawn-error', { error: String(e) }));
    p.on('exit', (c) => { if (!done) finish('exit', { code: c }); });
    const send = (o) => p.stdin.write(JSON.stringify(o) + '\n');
    const call = (id, method, params) => new Promise((res) => { pending.set(id, res); send({ jsonrpc: '2.0', id, method, params }); });
    (async () => {
      const init = await call(1, 'initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'verify', version: '1' } });
      if (!init || !init.result) return finish('bad-init');
      send({ jsonrpc: '2.0', method: 'notifications/initialized' });
      const t = await call(2, 'tools/list', {});
      clearTimeout(timer);
      finish('ok', { name: init.result.serverInfo && init.result.serverInfo.name, version: init.result.serverInfo && init.result.serverInfo.version, tools: ((t && t.result && t.result.tools) || []).length });
    })().catch((e) => finish('error', { error: String(e) }));
  });
}

const craftCli = process.argv[2];
const reaVersion = process.argv[3];
const out = [];
out.push({ label: 'craft-anything', ...(await probe(craftCli, ['mcp'], 120000)) });
out.push({ label: 'rea', ...(await probe('cmd.exe', ['/d', '/c', 'npx', '--proxy=false', '-y', `rea-agents@${reaVersion}`, 'mcp'], 240000)) });
console.log(JSON.stringify(out));
'@ | Set-Content -Path $probe -Encoding UTF8

  $res = node $probe $cli $ReaVersion 2>$null | Out-String
  Remove-Item $probe -ErrorAction SilentlyContinue
  $start = $res.IndexOf('[')
  if ($start -ge 0) {
    foreach ($r in ($res.Substring($start) | ConvertFrom-Json)) {
      if ($r.state -eq 'ok') { Write-Host ("   {0}: ok  name={1} version={2} tools={3}" -f $r.label, $r.name, $r.version, $r.tools) -ForegroundColor Green }
      else { Write-Host ("   {0}: {1} {2}" -f $r.label, $r.state, $r.error) -ForegroundColor Red; $fail++ }
    }
  } else { Write-Host '   probe produced no result' -ForegroundColor Red; $fail++ }
}

Write-Host ''
if ($fail -eq 0) { Write-Host 'ALL CHECKS PASSED' -ForegroundColor Green; exit 0 }
else { Write-Host "$fail CHECK(S) NEED ATTENTION" -ForegroundColor Yellow; exit 1 }
