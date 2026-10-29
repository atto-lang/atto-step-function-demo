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
