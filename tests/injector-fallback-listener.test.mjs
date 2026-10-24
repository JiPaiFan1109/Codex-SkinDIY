import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync(new URL('../engine/scripts/injector.mjs', import.meta.url), 'utf8');

test('pause/resume keeps one load fallback listener per live session', () => {
  const pauseBlock = source.slice(
    source.indexOf('if (paused) {', source.indexOf('if (pauseChanged || payloadChanged)')),
    source.indexOf('} else {', source.indexOf('if (paused) {', source.indexOf('if (pauseChanged || payloadChanged)'))),
  );
  assert.match(pauseBlock, /fallbackTargets\.delete\(id\);/);
  assert.doesNotMatch(pauseBlock, /fallbackListeners\.delete\(id\);/);

  // A listener marker is cleared when a session is actually discarded, so a
  // later session can register its own listener safely.
  const cleanupBlock = source.slice(source.indexOf('if (!activeIds.has(id) || session.closed)'), source.indexOf('if (!paused && Date.now() - lastSessionAuditAt'));
  assert.match(cleanupBlock, /fallbackListeners\.delete\(id\);/);
});
