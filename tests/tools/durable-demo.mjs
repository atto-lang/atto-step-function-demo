#!/usr/bin/env node
/**
 * Process-restart memory demo. Uses a fixed synthetic evidence test fixture.
 * This is NOT a live GitHub attestation and NOT a multi-writer durable engine.
 */
import {readFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {JsonFileMemoryLedger} from '../reference/durable-memory.mjs';
import {GraphSimulator} from '../reference/graph-runtime.mjs';
import {createActors} from '../reference/actors.mjs';

const transient=process.argv[2]===undefined;
const root=transient?await mkdtemp(join(tmpdir(),'ores-memory-pipeline-')):null;
const file=transient?join(root,'memory.json'):process.argv[2];
const sourceSha='a'.repeat(40);
const evidenceVerifier=async ({tenantId,eventId,repo,sourceSha:source})=>
  tenantId==='tenant_a'&&eventId==='evt_1'&&repo==='demo_repo'&&
  source===sourceSha?
  {tenantId,eventId,repo,headSha:source,conclusion:'success',executedSteps:4}:null;
try {
  const ledger=await JsonFileMemoryLedger.open(file);
  const {handlers}=createActors({ledger,evidenceVerifier});
  const graph=JSON.parse(await readFile(
    new URL('../../graphs/agent-memory-pipeline.json',import.meta.url),'utf8'));
  const result=await new GraphSimulator(graph,handlers).run({
    tenantId:'tenant_a',eventId:'evt_1',repo:'demo_repo',sourceSha,
    ci:{headSha:sourceSha,conclusion:'success',executedSteps:4}
  });
  await ledger.close();
  const afterRestart=await JsonFileMemoryLedger.open(file);
  const recalled=await afterRestart.recall({tenantId:'tenant_a',repo:'demo_repo'});
  await afterRestart.close();
  console.log(JSON.stringify({
    note:'synthetic test verifier; no trusted CI attestation or database',
    status:result.status,stored:recalled.length,records:recalled
  },null,2));
  if(result.status!=='COMPLETED'||recalled.length!==1)process.exitCode=1;
} finally {
  if(transient)await rm(root,{recursive:true,force:true});
}
