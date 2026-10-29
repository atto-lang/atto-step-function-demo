import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

const root=fileURLToPath(new URL('..',import.meta.url));
const invoke=(script,...args)=>spawnSync(process.execPath,
  [fileURLToPath(new URL('../scripts/'+script,import.meta.url)),...args],
  {cwd:root,encoding:'utf8',timeout:15000,env:{...process.env}});
test('a second OS process recalls verified demo metadata after producer exits',async t=>{
  const dir=await mkdtemp(join(tmpdir(),'ores-memory-process-'));
  t.after(()=>rm(dir,{recursive:true,force:true}));
  const file=join(dir,'checkpoint.json');
  const producer=invoke('durable-demo.mjs',file);
  assert.equal(producer.status,0,producer.stderr);
  const consumer=invoke('recall-memory.mjs',file,'tenant_a','demo_repo');
  assert.equal(consumer.status,0,consumer.stderr);
  const data=JSON.parse(consumer.stdout);
  assert.equal(data.records.length,1);
  assert.equal(data.records[0].sourceSha,'a'.repeat(40));
  const other=invoke('recall-memory.mjs',file,'tenant_b','demo_repo');
  assert.equal(other.status,0,other.stderr);
  assert.deepEqual(JSON.parse(other.stdout).records,[]);
});
