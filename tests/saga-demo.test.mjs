import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {admitSaga,SagaSimulator} from './reference/saga-runtime.mjs';
import {createSagaActors} from './reference/saga-actors.mjs';
const spec = async () => JSON.parse(await readFile(new URL('../graphs/order-saga.json',import.meta.url),'utf8'));
const simulator = async actors => new SagaSimulator(await spec(), actors || createSagaActors());

test('saga schema accepts bounded fixed actor names and freezes graph',async()=>{
  const saga=admitSaga(await spec());
  assert.ok(Object.isFrozen(saga));
  assert.ok(Object.isFrozen(saga.steps[0]));
  const missing=await spec();delete missing.steps[0].compensate;
  assert.throws(()=>admitSaga(missing),/SAGA_COMPENSATION_REQUIRED/);
  const dup=await spec();dup.steps[1].id='reserve';
  assert.throws(()=>admitSaga(dup),/BAD_SAGA_STEP/);
});
test('successful saga follows all three actors with no compensation',async()=>{
  const run=await (await simulator()).run({orderId:'order_7'});
  assert.equal(run.status,'COMPLETED');
  assert.equal(run.data.inventory,'reserved');
  assert.equal(run.data.payment,'authorized');
  assert.equal(run.data.shipment,'created');
  assert.deepEqual(run.trace.map(e=>e.phase),['forward','forward','forward']);
});
test('known shipment rejection compensates payment BEFORE inventory',async()=>{
  const history=[];
  const handlers=createSagaActors();
  for(const key of ['void_payment_saga','release_inventory_saga']) {
    const impl=handlers[key];
    handlers[key]=async data=>{history.push(key);return impl(data);};
  }
  const run=await (await simulator(handlers)).run({orderId:'order_7',rejectShipping:true});
  assert.equal(run.status,'COMPENSATED');
  assert.deepEqual(history,['void_payment_saga','release_inventory_saga']);
  assert.equal(run.data.payment,'voided');
  assert.equal(run.data.inventory,'released');
  assert.equal(run.data.shipment,'not_created');
});
test('failed/timeout forward actor is ambiguous: no automatic compensation',async()=>{
  const handlers=createSagaActors();let compensated=0;
  handlers.ship_order_saga=async()=>{throw new Error('possible external effect')};
  handlers.void_payment_saga=async()=>{compensated++;return {tag:'ok',patch:{}}};
  const run=await (await simulator(handlers)).run({orderId:'order_7'});
  assert.equal(run.status,'RECONCILIATION_REQUIRED');
  assert.deepEqual(run.acknowledged,['reserve','payment']);
  assert.equal(compensated,0);
  const pending= createSagaActors(); pending.ship_order_saga=async()=>new Promise(()=>{});
  const timeout=await (await simulator(pending)).run({orderId:'order_7'},{taskDeadlineMs:5});
  assert.equal(timeout.status,'RECONCILIATION_REQUIRED');
});
test('compensation failure cannot be hidden and later reversals still attempted',async()=>{
  const handlers=createSagaActors();let inventoryReleased=false;
  handlers.void_payment_saga=async()=>{throw new Error('refusal')};
  handlers.release_inventory_saga=async data=>{
    inventoryReleased=true;return {tag:'ok',patch:{inventory:'released'}};
  };
  const run=await (await simulator(handlers)).run({orderId:'order_7',rejectShipping:true});
  assert.equal(run.status,'COMPENSATION_INCOMPLETE');
  assert.equal(inventoryReleased,true);
  assert.equal(run.data.payment,'authorized');
});
test('untrusted accessor config is rejected before any getter runs',async()=>{
  const saga=await spec();let reads=0;
  Object.defineProperty(saga.steps[0],'compensate',{enumerable:true,get(){reads++;throw Error('BAD')}});
  assert.throws(()=>admitSaga(saga),/BAD_SAGA_FIELDS/);
  assert.equal(reads,0);
});
