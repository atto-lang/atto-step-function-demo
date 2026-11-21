# Durable Step Functions M1 — execution and recovery contract

**Status:** DESIGN / M0 PROTOCOL FIXTURE ONLY. Durable persistence, recovery,
and real compiler execution are **not implemented or verified**.

## What now exists

`examples/oreslang/workflow-generation-fence.ores` is a **pure Oreslang**
isolated actor with a single `state` schema and exclusive
`self.handle_state(critical[write] |s| -> { ... })` transitions.
A synthetic one-incarnation test checks a fixed foreign message, duplicate
activation, checkpoint label, simulated epoch takeover, stale-epoch completion,
stale checkpoint replay and terminal completion. Messaging and retirement
occur after the state loan closes.

The native verifier requires the compiler to check and run the experimental
guest with byte-exact stdout `fence:synthetic-stale-rejected`, **separate**
from the 14 canonical workflow manifest cases and two state-loan negative
compiler checks. Those checks remain NOT_EXECUTED in source-org CI until an
actual trusted compiler/runner is available. This fixture **does not restart**
an actor or persist state; its fixed string messages do not authenticate
tenants, epochs, leases, receipts or approvals.

## Minimal durable M1 implementation

The durable component must be implemented in `.ores`. Host/backend code is
limited to the smallest necessary async storage/fdatasync/fsync primitives.
No JavaScript/Python workflow engine or host-driven state machine is allowed.

1. **Identity.** Every durable run has an authenticated capability binding
   `tenant_id`, `namespace_id`, `workflow_id`, and an unforgeable,
   monotonically increasing `generation`/lease. Literal message strings
   are never evidence of identity or an external receipt.
2. **Single owner.** One actor owns run state. All mutations occur under a
   compiler-enforced exclusive non-suspending state loan. The actor never
   sends, awaits, invokes external effects or retires within that loan.
3. **Atomic storage.** One transaction commits deduplicated inbox receipt,
   state transition, event sequence, pending outbox intent and timer changes.
   An acknowledgement is emitted only after an acknowledged durable commit.
4. **Effect safety.** A committed outbox intent is idempotently dispatched
   with a stable effect key. A crash after dispatch but before an authenticated
   result is **UNKNOWN**, never automatically retried as a new effect.
   Reconciliation must bind tenant, run, generation, effect key and outcome.
5. **Recovery.** On restart a new generation is durably fenced using a
   conditional store update, then the last committed state and unapplied
   events are restored. Stale owners/timers/receipts cannot mutate or publish.
6. **Boundedness.** Inbox/outbox/event queues, retries, timers and recovery
   replays are bounded. A corrupt/torn/ambiguous record quarantines the
   affected run/tenant without terminating the shared host or preventing
   healthy tenant progress.

## Required executable acceptance matrix

| ID | Fault or input | Oracle |
| --- | --- | --- |
| M1-01 | Start + commit + clean restart | Same run identity, phase and checkpoint sequence; exactly one committed transition |
| M1-02 | Crash before transaction commit | No acknowledged transition, intent, timer or output survives |
| M1-03 | Crash after durable intent but before dispatch | Replay sends the same stable idempotency key, not a fresh effect |
| M1-04 | Crash after dispatch but before authenticated result | Remains UNKNOWN; no blind replay or compensation |
| M1-05 | Concurrent recovery generation and stale owner | One owner wins storage CAS; old generation's message/timer/outbox is rejected |
| M1-06 | Duplicate inbox/receipt, foreign tenant or forged generation | No second state mutation or effect; foreign input denied |
| M1-07 | Cancellation while effect UNKNOWN | No unsafe compensation; reconciliation required |
| M1-08 | Partial WAL, storage failure, exhausted quota | Fail closed and quarantine affected run while healthy tenant advances |

Each case must include a failing negative variant, durable-store bytes/events,
exact guest source blob, compiler SHA-256 and provenance, run/attempt/job IDs,
nonzero executed runner steps, and byte-exact guest output. In-memory test
output or host-only storage tests are **not durability proof**.

## CI / governance boundaries

The source-org hosted Actions job still fails before any steps execute.
A source-free canary in private `beamscale/bmscl-compiler` previously
executed and was re-run successfully on 2026-10-31 (run 41008869494,
attempt 2, three completed job steps). That test contains **no private demo
source** and **no compiler**, and does not authorize copying source or
building on that carrier. No cross-org private source export is permitted
without independent approval of exact source SHA/tree, private destination,
allowed files, runner workflow, retention/deletion and security reviewer.
Protect `main`, require exact-head nonzero-step native CI and independent
approval before making the draft merge-ready.

## M1-00 — typed checkpoint candidate (pending real compiler evidence)

`examples/oreslang/checkpoint-candidate-m1.ores` defines immutable
`WorkflowRunIdentity` and `WorkflowCheckpointCandidate` class-shaped
metadata plus a pure `checkpoint_candidate_well_formed` guard. It rejects
empty identity fields, zero/negative generations, version/event sequence
gaps, missing delivery and event keys, and missing phase labels. Its expected
stdout is `checkpoint:typed-shape-only`, outside the canonical 14-case
manifest. Exact-head native `--check` and execution were added to the
verifier **but have NOT run** on a trusted compiler.

**Security invariant:** this validation **does not authenticate** a caller or
issue a generation lease. It does not deduplicate deliveries against durable
storage, persist snapshots, perform compare-and-swap, or acknowledge a commit.
None of M1-01–M1-08 is satisfied by this fixture. The next implementation
requires a trusted ingress capability and a minimal asynchronous atomic
storage primitive; both must execute and be proven before claiming M1.


## M1-00b — restricted PostgreSQL atomic checkpoint prototype

\`sql/workflow_m1_atomic_checkpoint.sql\` is a PostgreSQL-only implementation
candidate for the **storage transaction boundary**. It creates a restricted
\`workflow_m1\` schema, composite run keys, an atomic
\`apply_checkpoint\` function, and \`fence_recovery\` generation-CAS function.

A successful \`apply_checkpoint\` call inside an uncommitted transaction is
**not an ACK**. The trusted asynchronous backend must BEGIN with
\`synchronous_commit=on\`, call the function, await COMMIT, and only then
notify the Oreslang coordinator. It must authenticate tenant/namespace/run
and issue current-generation capabilities. No guest, PUBLIC, or generic app
role is granted access by this migration. No Oreslang storage port is wired.

One row-level run lock serializes the inbox deduplication, snapshot/version,
event, optional outbox effect intent, and optional timer intent. Duplicate,
stale generation, stale version, quarantine and boundedness are distinct
results. Uniqueness conflicts must abort the **entire** transaction. Recovery
conditionally increments generation and changes IN_FLIGHT effects to UNKNOWN,
never silently replaying ambiguous effects. Its CAS is **not** an authenticated
lease: trusted adapter authorization and genuine runtime fencing are missing.

**Limits/risks:** This is a proposed PostgreSQL adapter, not default Oreslang
runtime durability. It has not run on PostgreSQL 17 or under a native compiler.
It does not validate snapshot digests cryptographically, own the SQL pool,
enforce RLS/role-to-tenant binding, implement actual dispatch, re-arm timers,
prove disk fsync under crash, or prove independent healthy-tenant progress.
RLS/database role grants, operator migrations and stable idempotency receipts
are hard release prerequisites. Do not claim M1-01–M1-08 pass.

\`sql/workflow_m1_atomic_tests.sql\` has transactional, rollback-isolated
positive and negative SQL oracles. They are NOT crash/restart or real guest
evidence and MUST run only on a disposable, explicitly authorized database.


### Mandatory pre-migration disposable PostgreSQL 17 gate

The `ci/test-m1-postgres.sh` launcher now uses **one psql session**
for `sql/workflow_m1_disposable_guard.sql`, migration, and adversarial
tests with `ON_ERROR_STOP=1`. The gate requires a PostgreSQL 17 database
whose name matches `oreslang_m1_test_*`, an explicit database-owner comment
`ORESLANG_M1_DISPOSABLE_DB_V1`, non-superuser credentials, and no recovery
standby. The existing shell acknowledgement and PGSERVICE alone do not
authorize mutation. Provision a new throwaway database and set:
`COMMENT ON DATABASE oreslang_m1_test_example IS 'ORESLANG_M1_DISPOSABLE_DB_V1';`.
Only a designated test role should have CREATE privileges. Never mark or
use an existing production database as disposable.

The checkpoint storage function now enforces **post-decode** JSON limits:
65,536 bytes for serialized snapshot and 16,384 bytes for event payload.
The trusted asynchronous adapter must impose network/pre-decode and total
tenant budgets separately. The migration sets
`SET LOCAL synchronous_commit = on`; function APPLIED still isn't an ACK
until COMMIT completes. PostgreSQL server execution remains NOT_EXECUTED.

### Storage generation retirement (SQL prototype; not a scheduler gate)

The proposed `workflow_m1.outbox` and `workflow_m1.timers` rows now carry
an explicit `generation` recording the owner that created them. A recovery
CAS **within the same SQL transaction** retires old-generation work:

- `IN_FLIGHT` external effects become `UNKNOWN`: reconciliation is mandatory,
  never blind redelivery or compensation.
- `PREPARED` effects become `PAUSED`: they were not known to have been
  dispatched, but require explicit authenticated re-admission under the new
  generation instead of being picked up by an old dispatcher.
- `ARMED` timers become `CANCELLED`: the new owner must explicitly reconstruct
  and rearm intended timers under its own generation, with a fresh durable
  timer key. An old timer's identifier is retained for audit/deduplication.

These fail-closed SQL state transitions are **not** sufficient to prevent an
already-running dispatcher, timer service or process from performing an
external side effect. Such services must check a current, storage-enforced
fence at the actual mutation boundary; old-generation actor capabilities and
retired execution/IO pins must not carry over. No dispatcher, rearming API,
authenticated async adapter, or concurrent recovery CI tests are implemented.

Adversarial SQL source cases now include (a) a duplicate timer key injected
as the *last* insert after inbox, snapshot, event and outbox changes to prove
full statement rollback, (b) stale armed timers cancelled on epoch takeover,
(c) in-flight effects changed to UNKNOWN, (d) prepared-but-not-dispatched
effects changed to PAUSED, and (e) a role-switching superuser **session_user**
rejected by the disposable DB preflight. None is a PostgreSQL test receipt
until executed against a disposable PostgreSQL 17 server.
