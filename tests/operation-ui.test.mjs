import test from 'node:test';
import assert from 'node:assert/strict';
import * as injector from '../engine/scripts/injector.mjs';

test('explicit operation status repairs a missing host without failing the skin action',async()=>{
  assert.equal(typeof injector.presentOperationUi,'function','Operation UI callers need their status helper');
  const calls=[];
  const session={closed:false,async evaluate(expression){calls.push(expression);return {visible:!expression.includes('"action":"update"')};}};
  assert.equal(await injector.presentOperationUi(session,'1:1700000000000:1','success','Done'),true);
  assert.equal(calls.length,2,'Missing host should be recreated');
  assert.match(calls[1],/"action":"show"/);
});

test('status display failure cannot turn a completed skin action into a failure',async()=>{
  assert.equal(typeof injector.presentOperationUi,'function');
  assert.equal(await injector.presentOperationUi({closed:false,async evaluate(){throw Error('renderer closed');}},'1:1700000000000:1','success','Done'),false);
});
