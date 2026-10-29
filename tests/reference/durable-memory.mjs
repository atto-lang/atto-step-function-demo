/**
 * Single-writer, local-filesystem memory ledger for development/restart demos.
 * Atomic same-directory rename + fsync; NOT a database, distributed lock,
 * authenticated snapshot, or multi-process writer coordination protocol.
 */
import {readFile,open,mkdir,rename,unlink} from 'node:fs/promises';
import {dirname,resolve,join} from 'node:path';
import {randomUUID,createHash} from 'node:crypto';

const check=(ok,code)=>{if(!ok)throw new Error(code)};
const id=/^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/;
const repo=/^(?:[A-Za-z0-9_.-]+\/)?[A-Za-z0-9_.-]+$/;
const sha=/^[a-f0-9]{40}(?:[a-f0-9]{24})?$/;
const own=(o,k)=>Object.hasOwn(o,k);
const copy=value=>structuredClone(value);
const encoded=payload=>JSON.stringify(payload);
const digest=payload=>'sha256:'+createHash('sha256')
  .update(encoded(payload),'utf8').digest('hex');
const recordOf=value=>{
  check(value && typeof value==='object' && !Array.isArray(value) &&
    id.test(value.tenantId||'')&&id.test(value.eventId||'')&&
    repo.test(value.repo||'')&&sha.test(value.sourceSha||'')&&
    Number.isSafeInteger(value.executedSteps)&&value.executedSteps>0,
    'INVALID_MEMORY_RECORD');
  return {
    tenantId:value.tenantId,eventId:value.eventId,repo:value.repo,
    sourceSha:value.sourceSha,executedSteps:value.executedSteps,
    claim:'host_verified_metadata_only'
  };
};
const empty=()=>({schemaVersion:1,revision:0,records:{},indexed:[]});
const envelope=state=>({...state,digest:digest(state)});
const restore=json=>{
  check(json && json.schemaVersion===1 && Number.isSafeInteger(json.revision) &&
    json.revision>=0 && json.records && !Array.isArray(json.records) &&
    typeof json.records==='object' && Object.getPrototypeOf(json.records)===Object.prototype &&
    Array.isArray(json.indexed) && json.digest===digest({
      schemaVersion:json.schemaVersion,revision:json.revision,
      records:json.records,indexed:json.indexed
    }), 'CORRUPT_MEMORY_CHECKPOINT');
  check(Object.keys(json.records).length<=256 &&
    json.indexed.length<=256 && new Set(json.indexed).size===json.indexed.length,
    'MEMORY_QUOTA');
  for (const [key,value] of Object.entries(json.records)) {
    const validated=recordOf(value);
    check(key===validated.tenantId+'/'+validated.eventId &&
      encoded(validated)===encoded(value),'CORRUPT_MEMORY_RECORD');
  }
  for (const key of json.indexed)
    check(typeof key==='string' && own(json.records,key),'CORRUPT_MEMORY_INDEX');
  return {schemaVersion:1,revision:json.revision,
    records:copy(json.records),indexed:copy(json.indexed)};
};

export class JsonFileMemoryLedger {
  #file;
  #state;
  #tail=Promise.resolve();
  #closed=false;
  #uncertain=false;
  #faultHook;
  constructor(file,state,faultHook=null) {
    this.#file=file;
    this.#state=state;
    this.#faultHook=faultHook;
  }
  static async open(filename,{faultHook=null}={}) {
    check(typeof filename==='string'&&filename.length>0,'BAD_STORAGE_PATH');
    check(faultHook===null||typeof faultHook==='function','BAD_FAULT_HOOK');
    const file=resolve(filename);
    let state;
    try {state=restore(JSON.parse(await readFile(file,'utf8')));}
    catch(e) {
      if(e.code!=='ENOENT') throw e;
      state=empty();
    }
    return new JsonFileMemoryLedger(file,state,faultHook);
  }
  async #write(state) {
    const parent=dirname(this.#file);
    await mkdir(parent,{recursive:true,mode:0o700});
    const temp=join(parent,'.memory-'+randomUUID()+'.tmp');
    let handle,renamed=false;
    try {
      handle=await open(temp,'wx',0o600);
      await handle.writeFile(encoded(envelope(state))+'\n','utf8');
      await handle.sync();
      await handle.close();handle=null;
      if(this.#faultHook)await this.#faultHook('before_rename',state.revision);
      await rename(temp,this.#file);
      renamed=true;
      if(this.#faultHook)await this.#faultHook('after_rename',state.revision);
      const dir=await open(parent,'r');
      try {await dir.sync();}finally{await dir.close();}
    } catch(e) {
      if(handle) await handle.close().catch(()=>{});
      await unlink(temp).catch(()=>{});
      if(renamed) {
        // The file may already contain the new revision; never overwrite
        // it from a stale in-memory snapshot until a fresh reopen reconciles.
        this.#uncertain=true;
        throw new Error('MEMORY_COMMIT_OUTCOME_UNKNOWN');
      }
      throw e;
    }
  }
  async #commit(change) {
    check(!this.#closed,'MEMORY_STORE_CLOSED');
    const operation=this.#tail.then(async()=>{
      check(!this.#uncertain,'MEMORY_COMMIT_OUTCOME_UNKNOWN');
      const next=copy(this.#state);
      const {changed,result}=change(next);
      if(changed) {
        check(Number.isSafeInteger(next.revision+1),'MEMORY_VERSION_OVERFLOW');
        next.revision++;
        await this.#write(next);
        this.#state=next;
      }
      return result;
    });
    this.#tail=operation.catch(()=>{});
    return operation;
  }
  async remember(input) {
    const entry=recordOf(input),key=entry.tenantId+'/'+entry.eventId;
    return this.#commit(next=>{
      if(own(next.records,key)) {
        check(encoded(next.records[key])===encoded(entry),'MEMORY_REPLAY_CONFLICT');
        return {changed:false,result:key};
      }
      check(Object.keys(next.records).length<256,'MEMORY_QUOTA');
      Object.defineProperty(next.records,key,{
        value:entry,enumerable:true,writable:true,configurable:true
      });
      return {changed:true,result:key};
    });
  }
  async index(tenantId,memoryId) {
    return this.#commit(next=>{
      check(id.test(tenantId||'') && typeof memoryId==='string' &&
        memoryId.startsWith(tenantId+'/') && own(next.records,memoryId),
        'UNAUTHORIZED_MEMORY_INDEX');
      if(next.indexed.includes(memoryId))return {changed:false,result:false};
      next.indexed.push(memoryId);
      return {changed:true,result:true};
    });
  }
  async forget(tenantId,memoryId) {
    return this.#commit(next=>{
      check(id.test(tenantId||'') && typeof memoryId==='string' &&
        memoryId.startsWith(tenantId+'/'),'UNAUTHORIZED_MEMORY_DELETE');
      if(!own(next.records,memoryId))return {changed:false,result:false};
      delete next.records[memoryId];
      next.indexed=next.indexed.filter(x=>x!==memoryId);
      return {changed:true,result:true};
    });
  }
  async recall({tenantId,repo:project}) {
    check(id.test(tenantId||'')&&repo.test(project||''),'BAD_MEMORY_QUERY');
    await this.#tail;
    check(!this.#closed,'MEMORY_STORE_CLOSED');
    return this.#state.indexed.filter(key=>key.startsWith(tenantId+'/'))
      .map(key=>this.#state.records[key]).filter(v=>v.repo===project).map(copy);
  }
  async close() {
    // Revoke new admission synchronously. Already admitted writes drain
    // before close resolves, but racing new callers cannot extend shutdown.
    this.#closed=true;
    await this.#tail;
  }
  get size(){return Object.keys(this.#state.records).length;}
  get revision(){return this.#state.revision;}
}
