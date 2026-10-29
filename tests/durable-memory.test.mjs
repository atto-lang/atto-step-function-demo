import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readFile,writeFile,rm,stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {JsonFileMemoryLedger} from '../src/durable-memory.mjs';

const sha='a'.repeat(40);
const event=(tenantId='tenant_a',eventId='evt_a')=>({
  tenantId,eventId,repo:'org/project',sourceSha:sha,
  executedSteps:4
});
const fixture=async t=>{
  const root=await mkdtemp(join(tmpdir(),'ores-memory-demo-'));
  t.after(()=>rm(root,{recursive:true,force:true}));
  return join(root,'memory.json');
};
test('restart reopens persisted indexed facts with exact source evidence',async t=>{
  const file=await fixture(t);
  const first=await JsonFileMemoryLedger.open(file);
  const key=await first.remember(event());
  await first.index('tenant_a',key);
  assert.equal(first.size,1);
  assert.equal(first.revision,2);
  await first.close();
  const second=await JsonFileMemoryLedger.open(file);
  assert.equal(second.size,1);
  assert.deepEqual((await second.recall({tenantId:'tenant_a',repo:'org/project'}))[0],
    {...event(),claim:'host_verified_metadata_only'});
  await second.close();
});
test('replayed identical writes and index deliveries remain idempotent',async t=>{
  const file=await fixture(t),ledger=await JsonFileMemoryLedger.open(file);
  const key=await ledger.remember(event());
  assert.equal(await ledger.remember(event()),key);
  assert.equal(await ledger.index('tenant_a',key),true);
  assert.equal(await ledger.index('tenant_a',key),false);
  assert.equal(ledger.revision,2);
  await ledger.close();
});
test('conflicting event ID fails without corrupting prior authoritative record',async t=>{
  const file=await fixture(t),ledger=await JsonFileMemoryLedger.open(file);
  await ledger.remember(event());
  await assert.rejects(ledger.remember({...event(),sourceSha:'b'.repeat(40)}),
    /MEMORY_REPLAY_CONFLICT/);
  assert.equal(ledger.revision,1);
  await ledger.close();
  const restored=await JsonFileMemoryLedger.open(file);
  assert.equal(restored.size,1);
  await restored.close();
});
test('tenant-scoped indexing, cross-tenant retrieval and deletion deny leakage',async t=>{
  const file=await fixture(t),ledger=await JsonFileMemoryLedger.open(file);
  const a=await ledger.remember(event('tenant_a','same'));
  const b=await ledger.remember(event('tenant_b','same'));
  await ledger.index('tenant_a',a);
  await ledger.index('tenant_b',b);
  assert.equal((await ledger.recall({tenantId:'tenant_c',repo:'org/project'})).length,0);
  assert.equal((await ledger.recall({tenantId:'tenant_b',repo:'org/project'})).length,1);
  await assert.rejects(ledger.index('tenant_a',b),/UNAUTHORIZED_MEMORY_INDEX/);
  await assert.rejects(ledger.forget('tenant_a',b),/UNAUTHORIZED_MEMORY_DELETE/);
  assert.equal(await ledger.forget('tenant_a',a),true);
  assert.equal(await ledger.forget('tenant_a',a),false);
  assert.deepEqual(await ledger.recall({tenantId:'tenant_a',repo:'org/project'}),[]);
  await ledger.close();
  const restored=await JsonFileMemoryLedger.open(file);
  assert.equal((await restored.recall({tenantId:'tenant_b',repo:'org/project'})).length,1);
  assert.equal((await restored.recall({tenantId:'tenant_a',repo:'org/project'})).length,0);
  await restored.close();
});
test('crash injected before atomic rename preserves previous committed snapshot',async t=>{
  const file=await fixture(t);
  const first=await JsonFileMemoryLedger.open(file);
  const k=await first.remember(event());
  await first.index('tenant_a',k);
  await first.close();
  const failing=await JsonFileMemoryLedger.open(file,{faultHook:async stage=>{
    if(stage==='before_rename')throw new Error('SIMULATED_CRASH');
  }});
  await assert.rejects(failing.remember(event('tenant_a','next')),
    /SIMULATED_CRASH/);
  await failing.close();
  const resumed=await JsonFileMemoryLedger.open(file);
  assert.equal(resumed.size,1);
  assert.equal(resumed.revision,2);
  await resumed.close();
});
test('on-disk tampering or schema downgrade fails snapshot admission',async t=>{
  const file=await fixture(t),ledger=await JsonFileMemoryLedger.open(file);
  await ledger.remember(event());
  await ledger.close();
  const obj=JSON.parse(await readFile(file,'utf8'));
  obj.records['tenant_a/evt_a'].sourceSha='b'.repeat(40);
  await writeFile(file,JSON.stringify(obj));
  await assert.rejects(JsonFileMemoryLedger.open(file),/CORRUPT_MEMORY_CHECKPOINT/);
  obj.schemaVersion=0;
  await writeFile(file,JSON.stringify(obj));
  await assert.rejects(JsonFileMemoryLedger.open(file),/CORRUPT_MEMORY_CHECKPOINT/);
});
test('writes serialize within one instance and file remains private',async t=>{
  const file=await fixture(t),ledger=await JsonFileMemoryLedger.open(file);
  await Promise.all(Array.from({length:10},(_,i)=>
    ledger.remember(event('tenant_a','evt'+i))));
  assert.equal(ledger.size,10);
  assert.equal(ledger.revision,10);
  await ledger.close();
  const metadata=await stat(file);
  if(process.platform!=='win32')assert.equal(metadata.mode & 0o077,0);
  const reopened=await JsonFileMemoryLedger.open(file);
  assert.equal(reopened.size,10);
  await reopened.close();
});
test('closed store rejects new operations',async t=>{
  const file=await fixture(t),ledger=await JsonFileMemoryLedger.open(file);
  await ledger.close();
  await assert.rejects(ledger.remember(event()),/MEMORY_STORE_CLOSED/);
});

test('ambiguous commit after rename refuses further writes until fresh reopen',async t=>{
  const file=await fixture(t);
  const first=await JsonFileMemoryLedger.open(file);
  await first.remember(event());
  await first.close();
  const ambiguous=await JsonFileMemoryLedger.open(file,{faultHook:async stage=>{
    if(stage==='after_rename')throw new Error('SIMULATED_IO_FAILURE');
  }});
  await assert.rejects(ambiguous.remember(event('tenant_a','new')),
    /MEMORY_COMMIT_OUTCOME_UNKNOWN/);
  await assert.rejects(ambiguous.remember(event('tenant_a','later')),
    /MEMORY_COMMIT_OUTCOME_UNKNOWN/);
  await ambiguous.close();
  const restored=await JsonFileMemoryLedger.open(file);
  assert.equal(restored.size,2);
  assert.equal(restored.revision,2);
  await restored.close();
});

test('close immediately fences new writes while draining previously admitted work',async t=>{
  const file=await fixture(t);
  let release;
  const held=new Promise(resolve=>{release=resolve});
  let entered;
  const inWrite=new Promise(resolve=>{entered=resolve});
  const ledger=await JsonFileMemoryLedger.open(file,{faultHook:async stage=>{
    if(stage==='before_rename') {entered();await held;}
  }});
  const earlier=ledger.remember(event());
  await inWrite;
  const closing=ledger.close();
  await assert.rejects(ledger.remember(event('tenant_a','late')),
    /MEMORY_STORE_CLOSED/);
  release();
  await earlier;
  await closing;
  const recovered=await JsonFileMemoryLedger.open(file);
  assert.equal(recovered.revision,1);
  assert.equal(recovered.size,1);
  await recovered.close();
});
