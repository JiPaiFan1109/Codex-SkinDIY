import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import vm from 'node:vm';
import {makeFixture, fixture} from './support/renderer-fixture.mjs';
import {maintainSession} from '../engine/scripts/injector.mjs';
fixture.template = await fs.readFile(new URL('../engine/assets/renderer-inject.js', import.meta.url), 'utf8');

test('SPA removal repairs the same wallpaper layers without replacing their Blob', () => {
  for (const video of [false, true]) {
    const f = makeFixture();
    vm.runInNewContext(f.payloadFor(video ? {video:{url:'http://127.0.0.1:4567/'+'a'.repeat(64)+'/video.mp4'}} : {}), f.context);
    const state = f.window.__CODEX_DREAM_SKIN_STATE__;
    const layer = video ? state.videoFrame : state.imageLayer;
    if (video) { state.videoBlobUrl = 'blob:fixture-video'; state.attachVideoBlob(state.videoBlobUrl); }
    const originalSource = layer.src;
    layer.remove();
    state.videoOverlay.remove();
    layer.src = '';
    state.ensure();
    assert.equal(layer.parentElement, f.document.body);
    assert.equal(state.videoOverlay.parentElement, f.document.body);
    assert.equal(layer.src, originalSource);
    assert.equal(video ? state.videoFrame : state.imageLayer, layer);
    assert.equal(f.revoked.length, 0);
    state.cleanup();
    state.ensure();
    assert.equal(layer.parentElement, null, 'restore must not be undone by a late repair');
  }
});

test('video recovers unexpected pause, stall and media errors with bounded retries', () => {
  const f = makeFixture();
  let clock = 0;
  f.context.performance.now = () => clock;
  vm.runInNewContext(f.payloadFor({video:{url:'http://127.0.0.1:4567/'+'a'.repeat(64)+'/video.mp4'}}), f.context);
  const state = f.window.__CODEX_DREAM_SKIN_STATE__;
  const video = state.videoFrame;
  state.videoBlobUrl = 'blob:fixture-video'; state.attachVideoBlob(state.videoBlobUrl);
  let loads = 0; video.load = () => { loads++; }; video.currentTime = 0;
  const tick = [...f.intervals.values()][0].callback;
  video.paused = true; tick();
  assert.equal(video.paused, false);
  assert.equal(loads, 0, 'a simple pause should not reload the video');
  clock = 16000; tick();
  assert.equal(loads, 1, 'frozen playback must reload after the grace period');
  video.error = {code:3}; clock = 20000; tick();
  assert.equal(loads, 1, 'no tight reload loop');
  clock = 32000; tick(); assert.equal(loads, 2);
  f.document.hidden = true; clock = 60000; tick();
  assert.equal(loads, 2, 'hidden windows must not waste resources restarting playback');
  state.cleanup(); clock = 90000; tick();
  assert.equal(loads, 3, 'only cleanup load is allowed after restore');
});

test('watcher repairs lost runtime but leaves healthy runtime and excluded pages alone', async () => {
  let writes = 0;
  const healthy = {evaluate:async () => true};
  assert.equal(await maintainSession(healthy, 'payload'), true);
  const lost = {evaluate:async expression => {
    if (expression === 'payload') { writes++; return true; }
    if (expression.includes('const state =')) return false;
    return {codex:true};
  }};
  assert.equal(await maintainSession(lost, 'payload'), true);
  assert.equal(writes, 1);
  const excluded = {evaluate:async expression => {
    if (expression === 'payload') throw new Error('must not inject unrelated surface');
    return expression.includes('const state =') ? false : {codex:false, excludedPetSurface:true};
  }};
  assert.equal(await maintainSession(excluded, 'payload'), false);
});
