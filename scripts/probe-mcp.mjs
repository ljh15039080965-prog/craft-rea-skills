#!/usr/bin/env node
// Probe both MCP servers: JSON-RPC initialize + tools/list.
//
//   node scripts/probe-mcp.mjs <craft-anything-cli path> [reaVersion]
//
// Prints one JSON array. Exit code 0 when both answered.

import { spawn } from 'node:child_process';

function probe(command, args, timeoutMs) {
  return new Promise((resolve) => {
    const p = spawn(command, args, { stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true });
    let buf = '';
    let done = false;
    const pending = new Map();
    const finish = (state, extra = {}) => {
      if (done) return;
      done = true;
      try { p.kill(); } catch { /* ignore */ }
      resolve({ state, ...extra });
    };
    const timer = setTimeout(() => finish('timeout'), timeoutMs);

    p.stdout.on('data', (d) => {
      buf += d.toString('utf8');
      let i;
      while ((i = buf.indexOf('\n')) >= 0) {
        const line = buf.slice(0, i).trim();
        buf = buf.slice(i + 1);
        if (!line.startsWith('{')) continue;
        try {
          const m = JSON.parse(line);
          if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
        } catch { /* not a complete frame */ }
      }
    });
    p.stderr.on('data', () => { /* servers log progress here */ });
    p.on('error', (e) => finish('spawn-error', { error: String(e) }));
    p.on('exit', (c) => { if (!done) finish('exit', { code: c }); });

    const send = (o) => p.stdin.write(JSON.stringify(o) + '\n');
    const call = (id, method, params) => new Promise((res) => {
      pending.set(id, res);
      send({ jsonrpc: '2.0', id, method, params });
    });

    (async () => {
      const init = await call(1, 'initialize', {
        protocolVersion: '2025-06-18',
        capabilities: {},
        clientInfo: { name: 'craft-rea-verify', version: '1.0.0' },
      });
      if (!init || !init.result) return finish('bad-init');
      send({ jsonrpc: '2.0', method: 'notifications/initialized' });
      const t = await call(2, 'tools/list', {});
      clearTimeout(timer);
      const tools = (t && t.result && t.result.tools) || [];
      finish('ok', {
        name: init.result.serverInfo?.name,
        version: init.result.serverInfo?.version,
        protocol: init.result.protocolVersion,
        tools: tools.length,
        sample: tools.slice(0, 5).map((x) => x.name),
      });
    })().catch((e) => finish('error', { error: String(e) }));
  });
}

const craftCli = process.argv[2];
const reaVersion = process.argv[3] || '6.5.0';
if (!craftCli) {
  console.error('usage: node scripts/probe-mcp.mjs <craft-anything-cli path> [reaVersion]');
  process.exit(2);
}

const results = [];
results.push({ label: 'craft-anything', ...(await probe(craftCli, ['mcp'], 120000)) });
results.push({
  label: 'rea',
  ...(await probe('cmd.exe', ['/d', '/c', 'npx', '--proxy=false', '-y', `rea-agents@${reaVersion}`, 'mcp'], 240000)),
});

console.log(JSON.stringify(results, null, 2));
process.exit(results.every((r) => r.state === 'ok') ? 0 : 1);
