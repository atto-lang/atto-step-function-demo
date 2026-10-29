/**
 * Example JS actor handlers for the host-only graph simulator.
 * The equivalent Oreslang .ores actor fixtures are in examples/oreslang/.
 * MemoryLedger lives in this process only: no database, authentication, or real CI attestation.
 */
const check = (ok, code) => { if (!ok) throw new Error(code); };
const id = value => typeof value === 'string' && /^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/.test(value);
const repoId = value => id(value) ||
  (typeof value === 'string' && /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(value));
const sha = value => typeof value === 'string' && /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/.test(value);
const copy = value => structuredClone(value);

export class MemoryLedger {
  #records = new Map();
  #index = new Map();
  remember(record) {
    check(record && id(record.tenantId) && id(record.eventId) &&
      repoId(record.repo) && sha(record.sourceSha) && record.executedSteps > 0 &&
      Number.isSafeInteger(record.executedSteps), 'UNVERIFIED_MEMORY');
    const key = record.tenantId + '/' + record.eventId;
    const entry = Object.freeze({
      tenantId:record.tenantId,eventId:record.eventId,
      repo:record.repo,sourceSha:record.sourceSha,
      executedSteps:record.executedSteps,claim:'host_verified_metadata_only'
    });
    if (this.#records.has(key)) {
      check(JSON.stringify(this.#records.get(key)) === JSON.stringify(entry),
        'MEMORY_REPLAY_CONFLICT');
      return key;
    }
    check(this.#records.size < 256, 'MEMORY_QUOTA');
    this.#records.set(key,entry);
    return key;
  }
  index(tenantId, memoryId) {
    check(id(tenantId) && memoryId.startsWith(tenantId + '/') &&
      this.#records.has(memoryId), 'UNAUTHORIZED_MEMORY_INDEX');
    this.#index.set(memoryId,true);
  }
  recall({tenantId,repo}) {
    check(id(tenantId) && repoId(repo), 'BAD_MEMORY_QUERY');
    return [...this.#records.entries()]
      .filter(([key,entry]) => key.startsWith(tenantId + '/') &&
        entry.repo === repo && this.#index.has(key))
      .map(([,entry]) => copy(entry));
  }
  get size() { return this.#records.size; }
}

// A production verifier must fetch attested evidence from a trusted CI source.
 // Never choose the verifier from graph input or caller-provided prose.
export function createActors({ledger=new MemoryLedger(), evidenceVerifier=null}={}) {
  const grants = new Map();
  const keyOf = data => [data.tenantId,data.eventId,data.repo,data.sourceSha].join('/');
  const handlers = {
    validate_order: async data => ({
      tag:typeof data.orderId === 'string' && id(data.orderId) ? 'accepted' : 'rejected',
      patch:{validated:typeof data.orderId === 'string' && id(data.orderId)}
    }),
    reserve_inventory: async data => {
      check(data.validated === true, 'NO_VALIDATED_ORDER');
      return {tag:'reserved',patch:{inventory:'reserved'}};
    },
    authorize_payment: async data => {
      check(data.validated === true, 'NO_VALIDATED_ORDER');
      return {tag:'authorized',patch:{payment:'authorized'}};
    },
    capture_event: async data => ({
      tag:'captured',patch:{captured:true}
    }),
    verify_evidence: async data => {
      const claim = data.ci;
      const shape = id(data.tenantId) && id(data.eventId) && repoId(data.repo) &&
        sha(data.sourceSha) && claim && typeof claim === 'object' &&
        !Array.isArray(claim) && claim.headSha === data.sourceSha &&
        claim.conclusion === 'success' &&
        Number.isSafeInteger(claim.executedSteps) && claim.executedSteps > 0;
      if (!shape || typeof evidenceVerifier !== 'function')
        return {tag:'unverified',patch:{evidenceVerified:false}};
      let attested = null;
      try {
        // A separately injected provider is the only trust input.
        attested = await evidenceVerifier({
          tenantId:data.tenantId,eventId:data.eventId,repo:data.repo,
          sourceSha:data.sourceSha,runId:claim.runId,runAttempt:claim.runAttempt
        });
      } catch {
        return {tag:'unverified',patch:{evidenceVerified:false}};
      }
      let verified=attested && typeof attested === 'object' &&
        !Array.isArray(attested) &&
        attested.tenantId === data.tenantId &&
        attested.eventId === data.eventId &&
        attested.repo === data.repo &&
        attested.headSha === data.sourceSha &&
        attested.conclusion === 'success' &&
        Number.isSafeInteger(attested.executedSteps) &&
        attested.executedSteps > 0 &&
        attested.executedSteps === claim.executedSteps &&
        (claim.runId === undefined ||
         (attested.runId === claim.runId && attested.runAttempt === claim.runAttempt));
      if (verified) {
        const grantKey=keyOf(data);
        if(!grants.has(grantKey) && grants.size>=256) verified=false;
        else grants.set(grantKey, Object.freeze({
          tenantId:data.tenantId,eventId:data.eventId,repo:data.repo,
          sourceSha:data.sourceSha,executedSteps:attested.executedSteps
        }));
      }
      return {tag:verified?'verified':'unverified',patch:{evidenceVerified:!!verified}};
    },
    remember_fact: async data => {
      // A user-supplied evidenceVerified=true flag is never a capability.
      const grant=grants.get(keyOf(data));
      check(data.evidenceVerified === true && grant &&
        grant.tenantId===data.tenantId && grant.eventId===data.eventId &&
        grant.repo===data.repo && grant.sourceSha===data.sourceSha,
        'UNVERIFIED_MEMORY');
      // Consume synchronously, BEFORE asynchronous persistence. Otherwise
      // two concurrent remember_fact calls can both pass the same grant.
      // A failed/ambiguous storage commit must not restore the capability:
      // the caller must obtain fresh independent evidence to retry.
      grants.delete(keyOf(data));
      const memoryId=await ledger.remember(grant);
      return {tag:'stored',patch:{memoryId}};
    },
    index_fact: async data => {
      await ledger.index(data.tenantId,data.memoryId);
      return {tag:'indexed',patch:{indexed:true}};
    },
    prepare_release: async () => ({
      tag:'prepared',patch:{releasePrepared:true}
    }),
    publish_preview: async data => {
      check(data.releasePrepared === true, 'UNPREPARED_RELEASE');
      // Produces an intent-like illustration, NEVER a real publish/deploy operation.
      return {tag:'prepared',patch:{publishIntent:'preview_only'}};
    }
  };
  return {ledger,handlers};
}
