# Contracts, provenance and safety

## What runs

- `npm test`: source-free Node.js tests for graph validation, fan-out, choice, symbolic approval, multi-tenant memory isolation, malformed evidence, and bounded retry.
- `npm run demo`: process-local simulation with JS actor handler functions. It does not compile or dispatch Oreslang actors.
- `examples/oreslang/*.ores`: illustrative guest source. The order fixtures were copied byte-for-byte from Java PR #2241's unexecuted actor baseline. The memory actor fixture is a syntax-derived sample and is not a persistence implementation.

## What does not run

- No durable DB transaction, lease epoch, snapshot restore, workflow timer or crash recovery.
- No real actor reference authentication, true inbox admission, supervisor CONTROL, mailbox quota, cancellation or physical quiescence.
- No GitHub API CI attestation, permission-gated release/deploy, LLM ingestion, embedding search, vector index, data retention, or remote memory graph.
- No compiler/backend evidence for the `.ores` files and no five-backend parity.

The graph simulator's bounded retries **reinvoke a function** and are not durable, idempotent actor requests. A retry may repeat non-idempotent external side effects. Parallel execution is `Promise.all` and cannot implement Oreslang's actor scheduling guarantees.

## Memory record rules demonstrated

- Tenant, event and repository IDs are explicit. Memory is indexed only within the tenant.
- A candidate record must have a valid 40/64-digit SHA, a matching reported CI head and a positive number of reported executed steps. **These client fields alone never authorize memory admission.**
- The memory graph now **fails closed** without a separately injected `evidenceVerifier`; the verifier must return the same tenant/event/repository, source SHA and positive executed-step count, and its private grant (not the caller's `evidenceVerified` flag) is checked before recording memory. The CLI injects only a fixed synthetic test-verifier fixture. Real admission must fetch and verify authoritative runner/job attestations, signature/installation identity, authorization, expected branch and exact source commit/tree. Any application that chooses an untrusted verifier still forfeits authenticity.
- Invalid or inconsistent inputs route to quarantine. Caller-provided prose (including prompt injection) is not executed or promoted to an instruction.
- Replays with the same scoped event ID and same record are idempotent; differing records conflict.
- The in-memory ledger caps at 256 records. Production needs retention, deletion, migration, audit and a tenant-authorized index.

## Durable implementation requirements

Use the Oreslang common-source `DURABLE_WORKFLOW_ACTORS_V0` contract: stable `(tenant_id,workflow_id,run_id,node_id)` address, monotone fenced activation epoch, transactional inbox/state/outbox/timers, canonical snapshot hash and schema version, async side-effect admission, deduplication, capability-scoped signaling and explicit reconciliation. Never claim exactly-once external network effects from an inbox dedup key.

Keep PRs and platform reports marked **host-only** until actual Oreslang source execution is recorded with exact commit, tree, compiler and fixture SHAs. A GitHub Actions failure with zero executed steps is infrastructure evidence, not a compiler failure.

## Source provenance

The three order `.ores` examples originated in
`ores-truffle-oreslang/oreslang-source.java` draft PR #2241, exact head
`2aa81b73beb9c340ec89692312d1140dc764c781`, within the **same source organization**.

Expected Git blob SHAs:
- Sequential: `e8d9b1c0a870ff6a8d35ced1acf860f85fd7e42d`
- Parallel: `40fd43e4b73bb29c9dd896d954ec2101bf36b1d1`
- Rejection: `f95baeb8fd8d0dec826c58bbe0ba88a3b444948f`

This repository is private. Do not make it public or transfer private-source fixtures into another organization without a separate privacy/security approval.

## Graph input hardening

Source-free graph admission validates acyclic plain JSON objects, bounded
nesting (16), message sizes (32 KiB graphs; 16 KiB run inputs; 4 KiB signals;
8 KiB actor outputs), finite numbers and no nested prototype keys. It rejects
inherited object properties as approval signals. These checks narrow the
simulation's attack surface, but do not replace production transport
validation, timeouts, actor isolation, or memory resource metering.

The latest graph and memory test suite includes 18 targeted tests. All
18 passed when exact fetched GitHub blobs were executed by an isolated
V8 evaluator with explicit shims; native Node/GitHub Actions execution
is a distinct gate. Source-free host simulation does not establish guest
Oreslang semantics.


## Evidence adapter (implemented, source-free)

`src/github-evidence.mjs` exposes a policy-bound verifier and a read-only
GitHub REST reader. The verifier **retrieves** a run and all jobs from a
credentialed source independent of the agent message; it binds the expected
repository, tenant, run ID and attempt, exact head SHA, workflow identity,
completed success and at least one positively executed required test step.
It rejects mismatched/queued runs, run-attempt substitutions, foreign PR
head repositories, missing or truncated job lists, skipped/missing test steps
and API errors. It does **not** prove runner hardware trust, signer identity
or source binary reproducibility; it is metadata verification, not a signed
attestation. The CLI requires operator-provided read authorization.

`createActors` requires this separately injected evidence verifier and
creates a private **one-use** grant, capped to 256 pending entries. A
caller-provided `evidenceVerified:true` does not authorize memory writes.
The default CLI graph demo uses a fixed synthetic verifier; no real GitHub
access is implied by its happy path.

## File-backed restart demo (implemented; not production)

`JsonFileMemoryLedger` atomically replaces its local JSON snapshot and
fsyncs file and directory before acknowledging a write. It validates
versioned SHA-256 checksums on reopening, serializes writes within an
instance, limits entries to 256, indexes tenant-scoped records, rejects
conflicting replays and supports deletion. Checksum validation detects
accidental corruption, **not** malicious tampering by someone who can
rewrite the file and checksum. Treat the file as trusted, protect its parent
directory, and never put secrets into this demo's metadata.

The file adapter has **no interprocess lease/fencing**. Concurrent processes
must not write the same file. Crash immediately after atomic rename may
produce an ambiguous commit result that must be reconciled by reopening and
comparing record IDs. Database-grade durability, cross-process isolation,
RLS, crash/replay reconciliation and signed ingress are still missing.

`sql/durable_memory_v1.sql` is an **unexecuted schema proposal** for
PostgreSQL-run fencing, transactional inbox/state/outbox, CI evidence
foreign keys and memory lifecycle. It is not connected to this demo.

## Logical task cancellation

The graph simulator now supports a per-attempt `taskDeadlineMs` (1..60000)
and optional `abortSignal`. A timed-out task records a non-secret
`timeout` trace and retries within its bounded attempt count; an abort
returns `CANCELLED`. This only stops **awaiting the actor promise**.
It does not revoke arbitrary external effects, physically stop an actor or
ensure completed child teardown. Persistent scheduler/supervision semantics
belong to the compiled Oreslang guest runtime.

## Verification classification (2026-10-28)

- 23 graph/actor tests: PASS in isolated strict-mode JavaScript evaluation,
  with a JSON-clone shim, UTF-8 byte counter and native V8 timers.
- 8 GitHub evidence tests: PASS in isolated strict-mode JavaScript evaluation
  with independent injected run/job API fixtures.
- 8 durable-store tests: PASS in isolated V8 evaluation with a virtual
  filesystem, JSON clone and **noncryptographic** surrogate digest.
- **Not executed**: unmodified Node 22 suite against exact GitHub tree,
  local real-fs SHA-256/fsync proof, hosted CI workflow steps, PostgreSQL
  integration, compiled Java/Graal `.ores` actor fixtures, LLVM/.NET/WASM/
  Forge guest parity.

No cross-org private-source Git mirror is authorized by local tests or
an alternate working runner; security incident #22 remains a separate gate.
