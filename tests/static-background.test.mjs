import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';
import { makeFixture, fixture } from './support/renderer-fixture.mjs';
import { loadPayload } from '../engine/scripts/injector.mjs';
fixture.template=await fs.readFile(new URL('../engine/assets/renderer-inject.js',import.meta.url),'utf8');
test('an image-only theme displays its own background layer and restores it cleanly',()=>{
  const f=makeFixture();vm.runInNewContext(f.payloadFor(),f.context);
  const state=f.window.__CODEX_DREAM_SKIN_STATE__;
  const image=f.document.getElementById('codex-dream-skin-image');
  assert.ok(image,'static background element must exist');
  assert.equal(image.src,state.artUrl);
  assert.equal(image.getAttribute('aria-hidden'),'true');
  assert.equal(f.document.getElementById('codex-dream-skin-video-frame'),null);
  state.cleanup();
  assert.equal(f.document.getElementById('codex-dream-skin-image'),null);
  assert.ok(f.revoked.includes(state.artUrl));
});
test('switching from video to a static theme removes the video and its Blob',()=>{
  const f=makeFixture();vm.runInNewContext(f.payloadFor({video:{url:'http://127.0.0.1:9335/'+'a'.repeat(64)+'/video.mp4'}}),f.context);
  const old=f.window.__CODEX_DREAM_SKIN_STATE__;old.videoBlobUrl='blob:previous-video';
  vm.runInNewContext(f.payloadFor(),f.context);
  assert.ok(f.document.getElementById('codex-dream-skin-image'));
  assert.equal(f.document.getElementById('codex-dream-skin-video-frame'),null);
  assert.ok(f.revoked.includes('blob:previous-video'));
});
test('shipped default background builds a valid payload without personal paths',async()=>{
  const payload=await loadPayload(fileURLToPath(new URL('../engine/assets',import.meta.url)));
  assert.equal(payload.theme.id,'preset-neutral');
  assert.equal(payload.video,null);
  assert.doesNotMatch(payload.payload,/[A-Z]:[\\/]+Users[\\/]+|arina-hashimoto|桥本有菜/i);
});

test('static transparency reaches the image layer without fading the interface',()=>{
  for(const opacity of [0,0.35,1]){
    const f=makeFixture();vm.runInNewContext(f.payloadFor({imageOpacity:opacity}),f.context);
    assert.equal(f.document.getElementById('codex-dream-skin-image').getAttribute('style'),'opacity: '+String(opacity)+';');
    assert.equal(f.rootStyle.getPropertyValue('opacity'),'');
  }
});

test('theme loader preserves valid opacity and rejects invalid input',async()=>{
  const {tmpdir}=await import('node:os');const path=await import('node:path');
  const dir=await fs.mkdtemp(path.join(tmpdir(),'skin-opacity-'));
  try{
    await fs.copyFile(new URL('../engine/assets/demo-background.png',import.meta.url),path.join(dir,'image.png'));
    for(const value of [0,0.65,1]){
      await fs.writeFile(path.join(dir,'theme.json'),JSON.stringify({schemaVersion:1,id:'test',image:'image.png',imageOpacity:value}));
      assert.equal((await loadPayload(dir)).theme.imageOpacity,value);
    }
    for(const value of [-1,2,'0.5']){
      await fs.writeFile(path.join(dir,'theme.json'),JSON.stringify({schemaVersion:1,id:'test',image:'image.png',imageOpacity:value}));
      await assert.rejects(loadPayload(dir),/opacity/);
    }
  }finally{await fs.rm(dir,{recursive:true,force:true});}
});
test('background strength only adjusts the wallpaper shade layer',()=>{
  for(const shade of [0,0.5,1]){
    const f=makeFixture();vm.runInNewContext(f.payloadFor({imageShade:shade,imageOpacity:1}),f.context);
    assert.equal(f.document.getElementById('codex-dream-skin-video-overlay').getAttribute('style'),'opacity: '+shade+';');
    assert.equal(f.rootStyle.getPropertyValue('opacity'),'');
  }
});