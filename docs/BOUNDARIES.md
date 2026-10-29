# Contracts, provenance and safety

## What runs

- `npm test`: source-free Node.js tests for graph validation, fan-out, choice, symbolic approval, multi-tenant memory isolation, malformed evidence, and bounded retry.
- `npm run demo`: process-local simulation with JS actor handler functions. It does not compile or dispatch Oreslang actors.
- `examples/oreslang/*.ores`: illustrative guest source. The order fixtures were copied byte-for-byte from Java PR #2241's unexecuted actor baseline. The memory actor fixture is a syntax-derived sample and is not a persistence implementation.

## What does not run

- No **production database** transaction, distributed writer lease, fenced activation epoch, durable workflow timer, or authenticated recovery. A local single-writer JSON snapshot/restart demo exists, but is not production storage.
- No real actor reference authentication, true inbox admission, supervisor CONTROL, mailbox quota, cancellation or physical quiescence.
- No signed CI attestation, production permission-gated release/deploy, LLM ingestion, embedding search, vector index, enforced data retention, or remote memory graph. A read-only GitHub REST metadata adapter exists, but no exact-head source-org runner execution has been proven.
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

The draft has targeted host-only regression tests, including one-use grant races, storage-close races, job runner-allocation denial, CI-run replay, accessor-free JSON admission and NUL-key rejection. These newly added tests have **not** executed as a native exact-head Node 22 suite. GitHub runner-backed test execution remains a distinct release gate. Source-free host simulation does not establish guest
Oreslang semantics.


## Evidence adapter (implemented, source-free)

`src/github-evidence.mjs` exposes a policy-bound verifier and a read-only
GitHub REST reader. The verifier **retrieves** a run and all jobs from a
credentialed source independent of the agent message; it binds the expected
repository, tenant, run ID and attempt, exact head SHA, workflow identity,
completed success and at least one positively executed required test step.
It rejects mismatched/queued runs, run-attempt substitutions, foreign PR
head repositories, missing or truncated job lists, skipped/missing test steps,
missing job runner ID/name, and API errors. It does **not** prove runner hardware trust, signer identity
or source binary reproducibility; it is metadata verification, not a signed
attestation. The CLI requires operator-provided read authorization.

`createActors` requires this separately injected evidence verifier and
creates a private **one-use** grant, capped to 256 pending entries. The grant is now consumed before awaiting storage, and a verified CI run/attempt is bound to one logical event ID (up to 256 retained run bindings) to reject cross-event replay. A
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
must not write the same file. Crash immediately after atomic rename may produce an ambiguous commit result.
The adapter quarantines its writer in that case and refuses subsequent writes
until a fresh reopen can reconcile committed records. Database-grade durability, cross-process isolation,
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

## Verification classification (2026-10-28 / latest head)

- Pre-existing isolated V8 host-model checks are reported in the PR history but do **not** attest this updated source.
- New hardening patches and regression tests are committed to draft PR #1; these are **NOT_EXECUTED** as an exact-head native Node 22 suite.
- Latest observed source-org run `40819134294` completed with `node-contract.steps=null`, `runner_id=null` and no executable test evidence. This is **RUNNER_NOT_ALLOCATED/CI_INFRA_UNVERIFIED**, not a source test result.
- Native Node 22 execution, real fs/fsync crash proof, source-local runner-backed job receipts, Java/Graal .ores guest execution and other backends remain unverified.
- No cross-org private-source export is authorized merely by the existence of a funded alternative runner. The independent approval and P0 incident gates remain mandatory.
