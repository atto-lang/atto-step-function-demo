/**
 * Host-only, bounded saga example. No persistent state or external effect fencing.
 * A rejected business step is a known no-op; an exception/timeout is ambiguous
 * and demands reconciliation BEFORE any reverse actions are issued.
 */
import {GraphSimulator} from './graph-runtime.mjs';
const ID = /^[A-Za-z][A-Za-z0-9_-]{0,63}$/;
const check = (ok, code) => { if (!ok) throw new Error(code); };
const record = v => v !== null && typeof v === 'object' && !Array.isArray(v) &&
  (Object.getPrototypeOf(v) === Object.prototype || Object.getPrototypeOf(v) === null);
const fields = (v, allowed) => {
  check(record(v), 'BAD_SAGA_SHAPE');
  for (const key of Reflect.ownKeys(v)) {
    check(typeof key === 'string' && allowed.includes(key), 'BAD_SAGA_FIELDS');
    const desc = Object.getOwnPropertyDescriptor(v, key);
    check(desc.enumerable && Object.hasOwn(desc, 'value'), 'BAD_SAGA_FIELDS');
  }
};
const id = v => typeof v === 'string' && ID.test(v);
const attempts = v => v === undefined || (Number.isSafeInteger(v) && v >= 1 && v <= 3);
export function admitSaga(spec) {
  fields(spec, ['kind','name','version','steps']);
  check(spec.kind === 'saga' && id(spec.name) && spec.version === 1 &&
    Array.isArray(spec.steps) && spec.steps.length >= 2 && spec.steps.length <= 12,
    'BAD_SAGA');
  check(Reflect.ownKeys(spec.steps).length === spec.steps.length + 1,
    'BAD_SAGA_STEPS');
  const used = new Set();
  for (let i=0; i<spec.steps.length; i++) {
    const step = spec.steps[i];
    fields(step,['id','actor','compensate','maxAttempts','compensateMaxAttempts']);
    check(id(step.id) && id(step.actor) && !used.has(step.id) &&
      attempts(step.maxAttempts) && attempts(step.compensateMaxAttempts),
      'BAD_SAGA_STEP');
    used.add(step.id);
    check(i === spec.steps.length-1 ?
      (step.compensate === undefined || id(step.compensate)) : id(step.compensate),
    'SAGA_COMPENSATION_REQUIRED');
  }
  check(Buffer.byteLength(JSON.stringify(spec),'utf8') <= 8192, 'SAGA_BYTE_BUDGET');
  const safe = structuredClone(spec);
  Object.freeze(safe.steps);
  for (const step of safe.steps) Object.freeze(step);
  return Object.freeze(safe);
}

export class SagaSimulator {
  #saga;
  #actors;
  constructor(saga, actors) {
    this.#saga = admitSaga(saga);
    check(record(actors), 'INVALID_ACTOR_REGISTRY');
    this.#actors = actors;
  }
  async #invoke(actor, maxAttempts, state, options) {
    const graph = {name:'saga_step',version:1,start:'invoke',nodes:{
      invoke:{kind:'task',actor,next:'done',maxAttempts},
      done:{kind:'succeed'}
    }};
    const result = await new GraphSimulator(graph,this.#actors).run(state,options);
    const tasks = result.trace.filter(e => e.kind === 'task');
    const final = tasks.at(-1);
    const tag = result.status === 'COMPLETED' ? final?.result : null;
    return {result,tag,attempts:tasks.length};
  }
  async run(input, options={}) {
    let state = input;
    const trace = [], acknowledged = [];
    for (const step of this.#saga.steps) {
      const out = await this.#invoke(step.actor,step.maxAttempts || 1,state,options);
      trace.push({step:step.id,phase:'forward',status:out.result.status,
        attempts:out.attempts,tag:out.tag});
      if (out.result.status !== 'COMPLETED' ||
          (out.tag !== 'ok' && out.tag !== 'rejected')) {
        return {status:'RECONCILIATION_REQUIRED',failedAt:step.id,
          acknowledged:acknowledged.map(s=>s.id),data:state,trace};
      }
      state = out.result.data;
      if (out.tag === 'ok') {
        acknowledged.push(step);
        continue;
      }
      let incomplete = false;
      for (const prior of acknowledged.reverse()) {
        const undo = await this.#invoke(prior.compensate,
          prior.compensateMaxAttempts || 1,state,options);
        const ok = undo.result.status === 'COMPLETED' && undo.tag === 'ok';
        trace.push({step:prior.id,phase:'compensate',status:undo.result.status,
          attempts:undo.attempts,tag:undo.tag});
        if (ok) state=undo.result.data;
        else incomplete=true;
      }
      return {status:incomplete?'COMPENSATION_INCOMPLETE':'COMPENSATED',
        failedAt:step.id,data:state,trace};
    }
    return {status:'COMPLETED',data:state,trace};
  }
}
