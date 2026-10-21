import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { createHash } from 'node:crypto';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

async function runProbe({ delayedFirst = false, wrongIdentity = false }) {
  let requests = 0;
  const sockets = new Set();
  const timers = new Set();
  let ready;
  const connected = new Promise(resolve => { ready = resolve; });
  const server = http.createServer((req, res) => {
    if (req.url === '/json/list') { res.end('[]'); return; }
    if (req.url !== '/json/version') { res.writeHead(404).end(); return; }
    requests++;
    const reply = () => {
      if (res.destroyed) return;
      res.setHeader('Content-Type', 'application/json');
      res.end(JSON.stringify({ webSocketDebuggerUrl: `ws://127.0.0.1:${server.address().port}/devtools/browser/${wrongIdentity ? 'other-browser' : 'fixture-browser'}` }));
    };
    if (delayedFirst && requests === 1) timers.add(setTimeout(reply, 2300));
    else reply();
  });
  server.on('upgrade', (req, socket) => {
    sockets.add(socket);
    const accept = createHash('sha1').update(req.headers['sec-websocket-key'] + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
    socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + accept + '\r\n\r\n');
    socket.on('error', () => {});
    ready({ connected: true });
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const child = spawn(process.execPath, [fileURLToPath(new URL('../engine/scripts/injector.mjs', import.meta.url)),
    '--watch', '--port', String(server.address().port), '--browser-id', 'fixture-browser', '--timeout-ms', '5000'],
  { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
  let stderr = '';
  child.stdout.resume();
  child.stderr.on('data', data => { stderr += data; });
  const exited = new Promise(resolve => child.once('exit', code => resolve({ exited: true, code })));
  let deadline;
  try {
    const result = await Promise.race([connected, exited, new Promise(resolve => { deadline = setTimeout(() => resolve({ timedOut: true }), 8000); })]);
    return { result, requests, stderr };
  } finally {
    clearTimeout(deadline);
    for (const timer of timers) clearTimeout(timer);
    if (child.exitCode === null) child.kill();
    for (const socket of sockets) socket.destroy();
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
}

test('watcher retries an aborted initial identity probe instead of exiting before it can guard the renderer', async () => {
  const probe = await runProbe({ delayedFirst: true });
  assert.equal(probe.result.connected, true, 'Watcher exited before retry: ' + probe.stderr);
  assert.ok(probe.requests >= 2, 'Initial timeout was never retried');
});

test('watcher rejects a different browser identity without retrying or connecting', async () => {
  const probe = await runProbe({ wrongIdentity: true });
  assert.equal(probe.result.exited, true);
  assert.equal(probe.result.code, 1);
  assert.equal(probe.requests, 1);
  assert.match(probe.stderr, /CDP browser identity changed/);
});
