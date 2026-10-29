#!/usr/bin/env node
import {readFile} from 'node:fs/promises';
import {SagaSimulator} from '../src/saga-runtime.mjs';
import {createSagaActors} from '../src/saga-actors.mjs';
const saga=JSON.parse(await readFile(new URL('../graphs/order-saga.json',import.meta.url),'utf8'));
const scenarios=[
  {name:'success',payload:{orderId:'order_7'}},
  {name:'rejected',payload:{orderId:'order_7',rejectShipping:true}},
  {name:'ambiguous_error',payload:{orderId:'order_7'},error:true}
];
for(const scenario of scenarios) {
  const actors=createSagaActors();
  if(scenario.error) actors.ship_order_saga=async()=>{throw Error('unknown effect')};
  const result=await new SagaSimulator(saga,actors).run(scenario.payload);
  console.log(JSON.stringify({scenario:scenario.name,...result},null,2));
}
