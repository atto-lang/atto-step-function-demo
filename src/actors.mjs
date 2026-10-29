/**
 * Example JS actor handlers for the host-only graph simulator.
 * The equivalent Oreslang .ores actor fixtures are in examples/oreslang/.
 * MemoryLedger lives in this process only: no database, authentication, or real CI attestation.
 */
const check = (ok, code) => { if (!ok) throw new Error(code); };
const id = value => typeof value === 'string' && /^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/.test(value);
const sha = value => typeof value === 'string' && /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/.test(value);
const copy = value => structuredClone(value);

export class MemoryLedger {
  #records = new Map();
  #index = new Map();
  remember(record) {
    check(record && id(record.tenantId) && id(record.eventId) &&
      id(record.repo) && sha(record.sourceSha) && record.executedSteps > 0 &&
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
    check(id(tenantId) && id(repo), 'BAD_MEMORY_QUERY');
    return [...this.#records.entries()]
      .filter(([key,entry]) => key.startsWith(tenantId + '/') &&
        entry.repo === repo && this.#index.has(key))
      .map(([,entry]) => copy(entry));
  }
  get size() { return this.#records.size; }
}

export function createActors({ledger=new MemoryLedger()}={}) {
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
      const verified=id(data.tenantId) && id(data.eventId) && id(data.repo) &&
        sha(data.sourceSha) && data.ci &&
        data.ci.headSha === data.sourceSha &&
        data.ci.conclusion === 'success' &&
        Number.isSafeInteger(data.ci.executedSteps) && data.ci.executedSteps > 0;
      // Metadata is illustrative: an attacker can forge these fields without trusted ingress.
      return {tag:verified?'verified':'unverified',patch:{evidenceVerified:!!verified}};
    },
    remember_fact: async data => {
      check(data.evidenceVerified === true, 'UNVERIFIED_MEMORY');
      return {tag:'stored',patch:{memoryId:ledger.remember({
        tenantId:data.tenantId,eventId:data.eventId,repo:data.repo,
        sourceSha:data.sourceSha,executedSteps:data.ci.executedSteps
      })}};
    },
    index_fact: async data => {
      ledger.index(data.tenantId,data.memoryId);
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
