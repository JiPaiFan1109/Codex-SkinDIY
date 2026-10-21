import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { createHash, webcrypto } from 'node:crypto';
import { restoreVideoCache, persistVideoCache } from '../engine/scripts/video-cache.mjs';

const bytes = Buffer.from('verified video fixture');
const config = { fileSize: bytes.length, fileSha256: createHash('sha256').update(bytes).digest('hex') };
function fixture({ denied = false } = {}) {
  const records = new Map(), blobs = [], revoked = [];
  const store = { async match(key) { return records.get(key)?.clone(); }, async put(key, value) { records.set(key, value.clone()); }, async delete(key) { return records.delete(key); } };
  const state = { installToken:'current', attachVideoBlob(url) { this.attached = url; return true; } };
  const window = { __CODEX_DREAM_SKIN_STATE__:state };
  const context = vm.createContext({ window, Blob, Response, Uint8Array, crypto:webcrypto, setTimeout, clearTimeout,
    caches:{ async open() { if(denied) throw Error('storage denied'); return store; } },
    URL:{ createObjectURL(blob) { blobs.push(blob); return `blob:${blobs.length}`; }, revokeObjectURL(url) { revoked.push(url); } } });
  const run = async (fn, args) => { context.args=args; return vm.runInContext(`(${fn.toString()})(...args)`,context); };
  return { records, blobs, revoked, state, window, context, run };
}
test('reopens verified media across session URL changes without another upload', async () => {
  const f=fixture();
  await f.run(persistVideoCache,[new Blob([bytes]),config]);
  assert.equal(await f.run(restoreVideoCache,[config,'new-server-key','current']),true);
  assert.equal(f.state.videoBlobKey,'new-server-key');
  assert.deepEqual(Buffer.from(await f.blobs[0].arrayBuffer()),bytes);
});
test('corrupt cache with matching metadata is rejected and evicted', async () => {
  const f=fixture();
  await f.run(persistVideoCache,[new Blob([Buffer.alloc(bytes.length)]),config]);
  assert.equal(await f.run(restoreVideoCache,[config,'key','current']),false);
  assert.equal(f.blobs.length,0); assert.equal(f.records.size,0);
});
test('cache is bounded to one video and a changed selection misses', async () => {
  const f=fixture();
  await f.run(persistVideoCache,[new Blob([bytes]),config]);
  const next={fileSize:3,fileSha256:createHash('sha256').update('new').digest('hex')};
  await f.run(persistVideoCache,[new Blob(['new']),next]);
  assert.equal(f.records.size,1);
  assert.equal(await f.run(restoreVideoCache,[config,'old','current']),false);
});
test('unavailable or hung cache falls back without attaching late results', async () => {
  const f=fixture({denied:true});
  assert.equal(await f.run(restoreVideoCache,[config,'key','current']),false);
  await f.run(persistVideoCache,[new Blob([bytes]),config]);
  f.context.caches.open=()=>new Promise(()=>{});
  assert.equal(await f.run(restoreVideoCache,[config,'key','current',10]),false);
  assert.equal(f.blobs.length,0);
});
test('pause and replaced runtime never receive cached media', async () => {
  const f=fixture(); await f.run(persistVideoCache,[new Blob([bytes]),config]);
  f.window.__CODEX_DREAM_SKIN_DISABLED__=true;
  assert.equal(await f.run(restoreVideoCache,[config,'key','current']),false);
  f.window.__CODEX_DREAM_SKIN_DISABLED__=false; f.state.installToken='replacement';
  assert.equal(await f.run(restoreVideoCache,[config,'key','current']),false);
  assert.equal(f.blobs.length,0);
});
test('failed cache attachment revokes its URL and preserves existing media', async () => {
  const f=fixture(); await f.run(persistVideoCache,[new Blob([bytes]),config]);
  f.state.videoBlobUrl='blob:old';f.state.videoBlobKey='old-key';
  f.state.attachVideoBlob=()=>{throw Error('attachment failed')};
  assert.equal(await f.run(restoreVideoCache,[config,'key','current']),false);
  assert.equal(f.state.videoBlobUrl,'blob:old'); assert.equal(f.state.videoBlobKey,'old-key');
  assert.deepEqual(f.revoked,['blob:1']);
});

test('cache result arriving after timeout cannot overwrite a newer upload', async () => {
  const f=fixture(); await f.run(persistVideoCache,[new Blob([bytes]),config]);
  const response=[...f.records.values()][0].clone();
  let finish;
  f.context.caches.open=async()=>({match:()=>new Promise(resolve=>{finish=resolve})});
  assert.equal(await f.run(restoreVideoCache,[config,'old','current',10]),false);
  f.state.videoBlobUrl='blob:newer';f.state.videoBlobKey='newer';
  finish(response);
  await new Promise(resolve=>setTimeout(resolve,25));
  assert.equal(f.blobs.length,0); assert.equal(f.state.videoBlobUrl,'blob:newer');
});

test('runtime replaced while cache is reading stays untouched', async () => {
  const f=fixture(); await f.run(persistVideoCache,[new Blob([bytes]),config]);
  const original=f.context.caches.open;
  let finish;
  f.context.caches.open=()=>new Promise(resolve=>{finish=resolve});
  const pending=f.run(restoreVideoCache,[config,'old','current']);
  f.window.__CODEX_DREAM_SKIN_STATE__={installToken:'replacement'};
  finish(await original());
  assert.equal(await pending,false);assert.equal(f.blobs.length,0);
});
