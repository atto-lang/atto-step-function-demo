import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';

const ledgerModule=pathToFileURL(fileURLToPath(new URL('../src/durable-memory.mjs',import.meta.url))).href;
const run=(script,file)=>spawnSync(process.execPath,['--input-type=module','--eval',script,file],
  {encoding:'utf8',timeout:15_000,env:{...process.env}});

test('an independent Node process recovers exactly committed, tenant-scoped memory',async t=>{
  const root=await mkdtemp(join(tmpdir(),'ores-native-process-'));
  t.after(()=>rm(root,{force:true,recursive:true}));
  const file=join(root,'ledger.json');
  const producer=run(`import {JsonFileMemoryLedger} from ${JSON.stringify(ledgerModule)};
    const ledger=await JsonFileMemoryLedger.open(process.argv[1]);
    const key=await ledger.remember({tenantId:'tenant_a',eventId:'build_1',
      repo:'org/project',sourceSha:'a'.repeat(40),executedSteps:5});
    await ledger.index('tenant_a',key);
    await ledger.close();
    console.log('COMMITTED');`,file);
  assert.equal(producer.status,0,producer.stderr);
  assert.match(producer.stdout,/COMMITTED/);

  const consumer=run(`import {JsonFileMemoryLedger} from ${JSON.stringify(ledgerModule)};
    const ledger=await JsonFileMemoryLedger.open(process.argv[1]);
    const own=await ledger.recall({tenantId:'tenant_a',repo:'org/project'});
    const other=await ledger.recall({tenantId:'tenant_b',repo:'org/project'});
    await ledger.close();
    console.log(JSON.stringify({own,other}));`,file);
  assert.equal(consumer.status,0,consumer.stderr);
  const recovered=JSON.parse(consumer.stdout);
  assert.equal(recovered.own.length,1);
  assert.equal(recovered.own[0].eventId,'build_1');
  assert.equal(recovered.own[0].sourceSha,'a'.repeat(40));
  assert.deepEqual(recovered.other,[]);
});
