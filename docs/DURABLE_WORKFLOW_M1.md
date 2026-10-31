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
