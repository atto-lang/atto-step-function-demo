// Structural test only: not an Oreslang parser, type checker or guest executor.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readdir,readFile} from 'node:fs/promises';
const root=new URL('../src/',import.meta.url);
const files=(await readdir(root)).sort();
const sources=await Promise.all(files.map(async filename=>({
 filename,source:await readFile(new URL(filename,root),'utf8')
})));
test('all implementation source files are Oreslang, no JavaScript engine in src',()=>{
 assert.deepEqual(files,[
  'memory_pipeline.ores','order_workflow.ores',
  'review_workflow.ores','saga_workflow.ores','step_graph.ores'
 ]);
 for(const {source} of sources)assert.doesNotMatch(source,/node:|require\(|import \* as/);
});
test('order Oreslang workflow owns validation, routing, fork and join actors',()=>{
 const s=sources.find(x=>x.filename==='order_workflow.ores').source;
 for(const actor of ['ValidateOrderStep','WorkflowRouter','InventoryStep','PaymentStep','JoinStep'])
  assert.match(s,new RegExp('define actor '+actor+' as'));
 assert.match(s,/if validated\.value != "validated"/);
 assert.match(s,/inventory\.send\(route\.value\)/);
 assert.match(s,/payment\.send\(route\.value\)/);
 assert.match(s,/await inventory\.get_done\(\)/);
 assert.match(s,/await payment\.get_done\(\)/);
});
test('memory Oreslang actor fails closed without trusted CI capability',()=>{
 const s=sources.find(x=>x.filename==='memory_pipeline.ores').source;
 assert.match(s,/define actor VerifyEvidenceStep/);
 assert.match(s,/self\.send\("unverified"\)/);
 assert.match(s,/define actor QuarantineStep/);
 assert.doesNotMatch(s,/self\.send\("verified"\)/);
});
test('review gate never deploys from unauthenticated string',()=>{
 const s=sources.find(x=>x.filename==='review_workflow.ores').source;
 assert.match(s,/self\.send\("waiting-approval"\)/);
 assert.doesNotMatch(s,/\bdeploy\(/);
 assert.doesNotMatch(s,/\bpublish\(/);
});
test('workflow graph transition rules are authored in Oreslang',()=>{
 const s=sources.find(x=>x.filename==='step_graph.ores').source;
 for(const name of ['order_next','memory_next','review_next'])
  assert.match(s,new RegExp('pub fnc '+name+'\\('));
 assert.match(s,/return "quarantine";/);
});

test('Oreslang saga owns the compensation actors',()=>{
 const s=sources.find(x=>x.filename==='saga_workflow.ores').source;
 for(const actor of ['ReserveInventorySagaStep','AuthorizePaymentSagaStep',
   'ShipOrderSagaStep','VoidPaymentSagaStep','ReleaseInventorySagaStep'])
   assert.match(s,new RegExp('define actor '+actor+' as'));
 assert.match(s,/voider.send\(payment_ack.value\)/);
 assert.match(s,/releaser.send\(inventory_ack.value\)/);
});
