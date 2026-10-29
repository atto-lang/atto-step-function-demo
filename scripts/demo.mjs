#!/usr/bin/env node
import {readFile} from 'node:fs/promises';
import {GraphSimulator,admitGraph} from '../tests/reference/graph-runtime.mjs';
import {createActors} from '../tests/reference/actors.mjs';

const scenario = process.argv[2] || 'all';
const read = async name => JSON.parse(await readFile(
  new URL('../graphs/' + name + '.json', import.meta.url),'utf8'));
const proofSha = 'a'.repeat(40);
// Deterministic TEST FIXTURE only: this is not GitHub's CI API or an attestation.
// It is injected out of band so caller-submitted CI claims cannot make themselves trusted.
const demoVerifier = async ({tenantId,eventId,repo,sourceSha}) => (
  tenantId==='tenant_a' && eventId==='event_1' && repo==='project_a' &&
  sourceSha===proofSha
  ? {tenantId,eventId,repo,headSha:proofSha,conclusion:'success',executedSteps:4}
  : null
);
const {ledger,handlers} = createActors({evidenceVerifier:demoVerifier});

async function run(name, input, options={}) {
  const graph = await read(name);
  const result = await new GraphSimulator(graph,handlers).run(input,options);
  return {graph:graph.name,status:result.status,data:result.data,trace:result.trace,
    waitingFor:result.waitingFor};
}

const outputs=[];
if (scenario==='all' || scenario==='order') {
  outputs.push(await run('order-pipeline',{orderId:'order-7'}));
  outputs.push(await run('order-pipeline',{orderId:''}));
}
if (scenario==='all' || scenario==='memory') {
  outputs.push(await run('agent-memory-pipeline',{
    tenantId:'tenant_a',eventId:'event_1',repo:'project_a',sourceSha:proofSha,
    ci:{headSha:proofSha,conclusion:'success',executedSteps:4}
  }));
  outputs.push({recall:ledger.recall({tenantId:'tenant_a',repo:'project_a'})});
}
if (scenario==='all' || scenario==='approval') {
  outputs.push(await run('release-review-pipeline',{}));
  outputs.push(await run('release-review-pipeline',{},
    {signals:{reviewed:{authority:'release_reviewer',approved:true}}}));
}
if (!['all','order','memory','approval','verify'].includes(scenario))
  throw new Error('UNKNOWN_SCENARIO');
if (scenario==='verify') {
  for (const graph of ['order-pipeline','agent-memory-pipeline','release-review-pipeline'])
    outputs.push({admitted:admitGraph(await read(graph)).name});
}
console.log(JSON.stringify(outputs,null,2));
