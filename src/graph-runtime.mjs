/**
 * Host-only, source-free Step Functions graph simulator.
 * It does NOT spawn Oreslang actors, persist state, or authenticate signals.
 */
const isRecord = value => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && (Object.getPrototypeOf(value) === Object.prototype ||
  Object.getPrototypeOf(value) === null);
const idPattern = /^[A-Za-z][A-Za-z0-9_-]{0,63}$/;
const check = (valid, code) => { if (!valid) throw new Error(code); };
const ident = value => typeof value === 'string' && idPattern.test(value);
const clone = value => structuredClone(value);
const freeze = value => {
  if (isRecord(value) || Array.isArray(value)) {
    for (const item of Object.values(value)) freeze(item);
    Object.freeze(value);
  }
  return value;
};
const keys = (value, allowed) => check(isRecord(value) &&
  Object.keys(value).every(key => allowed.includes(key)), 'INVALID_FIELDS');
const set = (obj, key, value) => Object.defineProperty(obj, key,
  {value, enumerable:true, writable:true, configurable:true});
// Validate before cloning. A transport must not accept functions, cyclic data,
// nonfinite numbers, class instances, nested prototype keys, or huge payloads.
const boundedJson = (value, maxBytes) => {
  const seen=new WeakSet();
  const walk=(v,depth)=>{
    check(depth<=16, 'JSON_DEPTH_BUDGET');
    if(v===null || typeof v==='string' || typeof v==='boolean') return;
    if(typeof v==='number') { check(Number.isFinite(v), 'NON_JSON_VALUE'); return; }
    check(Array.isArray(v) || isRecord(v), 'NON_JSON_VALUE');
    check(!seen.has(v), 'CYCLIC_JSON');
    seen.add(v);
    // Descriptor inspection avoids executing getter side effects during admission.
    const descriptors=Object.getOwnPropertyDescriptors(v);
    const ownKeys=Reflect.ownKeys(descriptors);
    check(ownKeys.length <= (Array.isArray(v) ? 257 : 256),
      'JSON_COLLECTION_BUDGET');
    for(const k of ownKeys) {
      if(Array.isArray(v) && k==='length') continue;
      check(typeof k==='string', 'NON_JSON_VALUE');
      const descriptor=descriptors[k];
      check(descriptor.enumerable && Object.hasOwn(descriptor,'value'),
        'NON_JSON_VALUE');
      check(!['__proto__','constructor','prototype'].includes(k) &&
        !k.includes('\0'), 'UNSAFE_JSON_KEY');
      walk(descriptor.value,depth+1);
    }
  };
  walk(value,0);
  check(Buffer.byteLength(JSON.stringify(value),'utf8')<=maxBytes, 'JSON_BYTE_BUDGET');
};

export function admitGraph(graph) {
  boundedJson(graph,32768);
  keys(graph, ['name','version','start','nodes']);
  check(ident(graph.name) && graph.version === 1 && ident(graph.start) &&
    isRecord(graph.nodes), 'INVALID_GRAPH');
  const entries = Object.entries(graph.nodes);
  check(entries.length > 0 && entries.length <= 64 &&
    entries.every(([name]) => ident(name)) && Object.hasOwn(graph.nodes, graph.start),
    'GRAPH_BUDGET_OR_START');
  const edges = new Map(entries.map(([name]) => [name, []]));
  const branchOwners = new Map();
  const edge = (from, to) => {
    check(ident(to), 'BAD_EDGE');
    edges.get(from).push(to);
  };
  for (const [name, node] of entries) {
    check(isRecord(node), 'INVALID_NODE');
    if (node.kind === 'task') {
      keys(node, ['kind','actor','next','onError','maxAttempts']);
      check(ident(node.actor) && (node.next === null || ident(node.next)) &&
        (node.onError === undefined || ident(node.onError)) &&
        (node.maxAttempts === undefined ||
          (Number.isSafeInteger(node.maxAttempts) && node.maxAttempts >= 1 &&
           node.maxAttempts <= 5)), 'BAD_TASK');
      if (node.next !== null) edge(name, node.next);
      if (node.onError !== undefined) edge(name, node.onError);
    } else if (node.kind === 'choice') {
      keys(node, ['kind','routes','otherwise']);
      check(isRecord(node.routes) && Object.keys(node.routes).length > 0 &&
        Object.keys(node.routes).length <= 16 && ident(node.otherwise),
        'BAD_CHOICE');
      for (const [tag, target] of Object.entries(node.routes)) {
        check(ident(tag), 'BAD_CHOICE_TAG');
        edge(name, target);
      }
      edge(name, node.otherwise);
    } else if (node.kind === 'parallel') {
      keys(node, ['kind','branches','next']);
      check(Array.isArray(node.branches) && node.branches.length >= 2 &&
        node.branches.length <= 8 && new Set(node.branches).size === node.branches.length,
        'BAD_PARALLEL');
      for (const b of node.branches) {
        check(ident(b) && !branchOwners.has(b), 'BAD_PARALLEL_BRANCH');
        branchOwners.set(b, name);
        edge(name, b);
      }
      edge(name, node.next);
    } else if (node.kind === 'wait') {
      keys(node, ['kind','signal','authority','next']);
      check(ident(node.signal) && ident(node.authority), 'BAD_WAIT');
      edge(name, node.next);
    } else if (node.kind === 'succeed' || node.kind === 'fail') {
      keys(node, ['kind']);
    } else throw new Error('UNKNOWN_NODE_KIND');
  }
  for (const targets of edges.values()) {
    for (const target of targets) check(Object.hasOwn(graph.nodes, target), 'UNKNOWN_TARGET');
  }
  for (const [branch] of branchOwners) {
    const node = graph.nodes[branch];
    check(node.kind === 'task' && node.next === null && node.onError === undefined &&
      branch !== graph.start && [...edges.values()].filter(ts => ts.includes(branch)).length === 1,
      'PARALLEL_BRANCH_NOT_EXCLUSIVE');
  }
  for (const [name, node] of entries) {
    if (node.kind === 'task' && node.next === null)
      check(branchOwners.has(name), 'UNJOINED_TASK');
  }
  const visited = new Set(), visiting = new Set();
  const visit = name => {
    check(!visiting.has(name), 'GRAPH_CYCLE');
    if (visited.has(name)) return;
    visiting.add(name);
    for (const target of edges.get(name)) visit(target);
    visiting.delete(name);
    visited.add(name);
  };
  visit(graph.start);
  check(visited.size === entries.length, 'UNREACHABLE_NODE');
  return freeze(clone(graph));
}

function cleanResponse(result) {
  boundedJson(result,8192);
  keys(result, ['tag','patch']);
  check(ident(result.tag) && (result.patch === undefined || isRecord(result.patch)),
    'BAD_ACTOR_RESPONSE');
  const patch = result.patch || {};
  check(Object.keys(patch).length <= 24 &&
    Object.keys(patch).every(k => ident(k) && !['constructor','prototype','__proto__'].includes(k)),
    'BAD_ACTOR_PATCH');
  return {tag:result.tag, patch:clone(patch)};
}

export class GraphSimulator {
  #graph;
  #actors;
  constructor(graph, actors) {
    this.#graph = admitGraph(graph);
    check(isRecord(actors), 'INVALID_ACTOR_REGISTRY');
    this.#actors = Object.freeze({...actors});
  }
  async run(input, {signals={},abortSignal=null,taskDeadlineMs=10_000}={}) {
    check(isRecord(input) && isRecord(signals), 'INVALID_INPUT');
    boundedJson(input,16384);
    boundedJson(signals,4096);
    check(Number.isSafeInteger(taskDeadlineMs) && taskDeadlineMs>=1 &&
      taskDeadlineMs<=60_000, 'BAD_TASK_DEADLINE');
    check(abortSignal===null ||
      (typeof abortSignal.aborted==='boolean' &&
       typeof abortSignal.addEventListener==='function' &&
       typeof abortSignal.removeEventListener==='function'), 'BAD_ABORT_SIGNAL');
    const cancelled=()=>abortSignal?.aborted===true;
    // Logical deadline/cancellation only: the actor function may continue
    // producing external effects after the simulator stops awaiting it.
    const withinBudget=async pending=>{
      if(cancelled())throw new Error('WORKFLOW_CANCELLED');
      let timer=null, onAbort;
      const watchdog=new Promise((_,reject)=>{
        timer=setTimeout(()=>reject(new Error('TASK_TIMEOUT')),taskDeadlineMs);
        if(abortSignal) {
          onAbort=()=>reject(new Error('WORKFLOW_CANCELLED'));
          abortSignal.addEventListener('abort',onAbort,{once:true});
        }
      });
      try{return await Promise.race([pending,watchdog]);}
      finally{
        clearTimeout(timer);
        if(abortSignal&&onAbort)abortSignal.removeEventListener('abort',onAbort);
      }
    };
    let data = clone(input), current = this.#graph.start, tag = 'start';
    const trace = [];
    const applyPatch = (original, patch) => {
      const next = clone(original);
      for (const [key,value] of Object.entries(patch)) set(next,key,clone(value));
      return next;
    };
    const task = async (id, node, payload) => {
      const actor = Object.hasOwn(this.#actors, node.actor) ? this.#actors[node.actor] : null;
      check(typeof actor === 'function', 'UNKNOWN_ACTOR');
      const attempts = node.maxAttempts || 1;
      const history = [];
      for (let attempt=1; attempt<=attempts; attempt++) {
        try {
          const response = cleanResponse(await withinBudget(Promise.resolve().then(()=>
            actor(clone(payload),{nodeId:id,attempt,abortSignal}))));
          history.push({nodeId:id,kind:'task',attempt,result:response.tag});
          return {response,history};
        } catch (err) {
          if(cancelled()||err?.message==='WORKFLOW_CANCELLED')
            return {response:null,history,cancelled:true};
          // Do not persist raw error messages: they can contain secrets or prompts.
          history.push({nodeId:id,kind:'task',attempt,
            result:err?.message==='TASK_TIMEOUT'?'timeout':'error'});
        }
      }
      return {response:null,history};
    };
    for (let steps=0; steps<128; steps++) {
      if(cancelled())return {status:'CANCELLED',data,trace};
      const id = current, node = this.#graph.nodes[id];
      if (node.kind === 'task') {
        const output = await task(id,node,data);
        trace.push(...output.history);
        if (output.cancelled)return {status:'CANCELLED',data,trace};
        if (!output.response) {
          if (!node.onError) return {status:'FAILED',data,trace,reason:'TASK_FAILED'};
          current = node.onError; tag = 'error';
        } else {
          data=applyPatch(data,output.response.patch);
          tag=output.response.tag;current=node.next;
        }
      } else if (node.kind === 'choice') {
        current=Object.hasOwn(node.routes,tag) ? node.routes[tag] : node.otherwise;
        trace.push({nodeId:id,kind:'choice',result:tag});
      } else if (node.kind === 'parallel') {
        // Branches execute concurrently. Output/trace projection is in graph order.
        const output = await Promise.all(node.branches.map(branch =>
          task(branch,this.#graph.nodes[branch],data)));
        if(cancelled()||output.some(item=>item.cancelled))
          return {status:'CANCELLED',data,trace};
        const patches=Object.create(null);
        for (let i=0;i<output.length;i++) {
          const result=output[i],branch=node.branches[i];
          trace.push(...result.history);
          if (!result.response)
            return {status:'FAILED',data,trace,reason:'PARALLEL_BRANCH_FAILED'};
          set(patches,branch,result.response.patch);
        }
        data=applyPatch(data,{parallel:patches});
        tag='joined';current=node.next;
        trace.push({nodeId:id,kind:'parallel',result:'joined'});
      } else if (node.kind === 'wait') {
        const signal=Object.hasOwn(signals,node.signal)?signals[node.signal]:undefined;
        if (signal === undefined)
          return {status:'WAITING',data,trace,waitingFor:node.signal};
        check(isRecord(signal) && signal.authority === node.authority &&
          signal.approved === true, 'BAD_SYMBOLIC_SIGNAL');
        // This is a symbolic demo, not an authenticated approval.
        trace.push({nodeId:id,kind:'wait',result:'symbolic_approval'});
        current=node.next;tag='approved';
      } else if (node.kind === 'succeed' || node.kind === 'fail') {
        trace.push({nodeId:id,kind:node.kind,result:node.kind});
        return {status:node.kind==='succeed'?'COMPLETED':'FAILED',data,trace};
      }
    }
    throw new Error('TRANSITION_BUDGET');
  }
}
