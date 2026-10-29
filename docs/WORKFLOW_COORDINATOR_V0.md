# Native WorkflowCoordinatorActor v0 — implementation contract

**Status: specification/implementation plan, not a compiled or implemented isolated actor.** Keep workflow graph semantics in native `.ores` under `ores.std/workflow`, not in Java, C#, Node, or a compiler-specific runtime. Java/Graal, LLVM, .NET and Wasm may supply only bounded storage, timer, crypto, network and allocator primitives.

## Actor execution / storage separation

- `define isolated actor WorkflowCoordinatorActor as ... end` is the desired actor declaration once supported by each compiler. Actor methods should not require `fnc`. Do not assume an arbitrary source sketch compiles until source tests execute.
- The coordinator owns private mutable workflow state in its own actor-owned arena/heap. Only typed messages cross actor boundaries; no borrows may escape or span suspension.
- Handlers are non-reentrant across all suspension points. Seal mutating access during transitions; do not rely on a JVM global heap or actor-scoped logical namespace as physical heap isolation.
- A stable `(tenant_id, workflow_id, run_id)` logical identity is separate from an activation's epoch or OS thread. A run pins a graph version, schema version, and code generation.
- A `WorkflowNode<In,Out,State>` is a library interface, not a new actor keyword. Compile/admit typed edges, deterministic branch outcomes, bounded parallelism, bounded retries, deadlines, and structured child ownership/cancellation.

## Atomic durable transition

1. Authenticate and authorize tenant/run and inbox delivery ID. Reject stale activation epoch, incompatible schema/graph version, duplicate receipt, and out-of-order delivery.
2. Under the actor lease, compute next sealed state, messages, timer metadata, and external effect intents as **pure native Oreslang values**.
3. Commit state version, consumed inbox offset, emitted events, outbox intents, timer changes, and fencing epoch check in one storage transaction through the backend adapter.
4. Dispatch outbox intents asynchronously, each with deterministic idempotency keys and receipts. External effects are not part of the database transaction.
5. For ambiguous activity outcomes, transition to `RECONCILIATION_REQUIRED`; never auto-retry or compensate until the effect is reconciled. Compensation is explicitly modeled as new bounded actions.

## Freeze / resume

`RUNNING → QUIESCING → DORMANT → RESTORING → RUNNING` at checkpoint-safe suspension only. Persist canonical versioned data and inbox/outbox cursors, not native stacks, borrowed references, file descriptors or raw arena pointers. Release an idle arena and reactivate with a new epoch. Validate the snapshot digest, tenant binding, schema and code generation, and migration before admitting handlers.

## Hardening gates

- Crash before/after commit and crash after external dispatch; no lost committed event, no doubled logical state transition.
- Duplicate/out-of-order delivery; stale epoch; cross-tenant attempt; poisoned restore digest; incompatible state migration; late activity receipt.
- Exactly-one graph branch winner, supervised child cancellation, mailbox and graph-wide quota limits, race/fuzz checks, and no automatic Future/Option flattening.
- Monotonic timer expiry **and bounded timer-to-user-code dispatch latency**; hard-RT paths must have explicit schedulability admission and reject unbounded allocation, blocking I/O or suspension.
- Actual Java/Graal guest tests first, then exact-tree LLVM/.NET/Wasm parity with executed jobs. Preserve independent private-source export authorization.

See `oreslang-common-source/docs/DURABLE_WORKFLOW_ACTORS_V0.md` for the canonical broader contract.

## Actor state ownership migration (source-contract stage)

The executable `workflows/coordinator-state.ores` sample now declares one
`state { phase: String = "created"; }` schema and performs an atomic
check-and-update using `self.handle_state(critical |s| -> { ... })`.
The resulting response is sent **after** the exclusive loan ends; neither
`self.send` nor `self.end` occurs inside the critical section. Every
other workflow actor in the native manifest is currently stateless and
requires no empty state block. This does **not** implement persistence or
prove that the compiler has lowered state loans; compile and execute the
exact guest before treating the workflow as runnable.

### Void callback compatibility

The first implemented state-loan feature in compiler draft #1806 requires a
**void inline lexical callback**. The coordinator now stores a detached local
`response` variable and calls `self.handle_state(...)` as a statement,
with `self.send` after loan closure, instead of returning a value from the
callback. This still depends on compiler support for a captured local reply
and the mandatory `critical` spelling; neither has yet been executed against
the reconciled compiler. Source-only CI cannot prove these semantics.

See compiler draft [#2245](https://github.com/ores-truffle-oreslang/oreslang-source.java/pull/2245).

### POSIX source-policy repair (October 29)

The earlier coordinator policy in `ci/audit-source.sh` contained a malformed multiline quoted `grep` expression and incorrectly escaped regular expressions. The source contract now uses literal `grep -F` where possible and scoped POSIX `awk` checks for exactly one loan, its closure, and a single post-loan reply. This is a static policy, not a native compile/runtime verdict. Run `sh -n ci/audit-source.sh`, `sh ci/audit-source.sh`, and the actual guest fixture in an approved repository checkout before enabling merge.
