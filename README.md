# Oreslang Step Functions — actors, graphs and AI-agent memory

A hands-on **actor-first workflow demo** for [Oreslang](https://github.com/ores-truffle-oreslang/oreslang-source.java). Includes three declarative DAGs, a source-free JavaScript graph simulator and tests, and Oreslang `.ores` actor-message examples.

> **Execution status:** The JavaScript code is a **host-only simulator**, not an Oreslang runtime or durable workflow engine. The Oreslang examples follow the Java/Graal source-actor baseline in [Java draft PR #2241](https://github.com/ores-truffle-oreslang/oreslang-source.java/pull/2241); actual guest execution is not yet independently verified. No API credentials are bundled; a separate read-only GitHub REST client can use operator-supplied credentials, but authenticated approvals and production persistence are not implemented.

## Try the demos

Install **Node.js 22+**; no npm dependencies are needed.

```bash
npm test
npm run verify
npm run demo
npm run test:memory
npm run demo:durable
# In another process, recover persisted records:
# node scripts/recall-memory.mjs /secure/local/path/memory.json tenant_a demo_repo
node scripts/demo.mjs order
node scripts/demo.mjs memory
node scripts/demo.mjs approval
```

`npm run demo` prints simulated traces for successful/rejected orders, a **test-fixture-attested** memory record, and approval waiting/preview. The demo's evidence verifier returns one fixed synthetic CI result; it is not connected to GitHub.

## Start here

| Example | Graph | Actors / source example | What it teaches |
|---|---|---|---|
| Order fulfillment | [order-pipeline.json](graphs/order-pipeline.json) | [sequential](examples/oreslang/order-sequential.ores), [parallel](examples/oreslang/order-parallel.ores), [rejection](examples/oreslang/order-rejected.ores) | Task → choice → parallel fork/join → success/failure |
| AI coding-agent memory | [agent-memory-pipeline.json](graphs/agent-memory-pipeline.json) | [memory actors](examples/oreslang/agent-memory-actors.ores) | Capture → verify revision + executed steps → quarantine or remember → index |
| Release review | [release-review-pipeline.json](graphs/release-review-pipeline.json) | [host handler definitions](src/actors.mjs) | Wait → symbolic approval → publish **preview intent** |

See [workflow diagrams](docs/GRAPHS.md) and [implementation and security boundaries](docs/BOUNDARIES.md).

## Project structure

```text
examples/oreslang/    # Actor classes/message-flow examples; guest execution unverified
graphs/               # Validated Step Functions-style JSON DAGs
src/graph-runtime.mjs # Bounded host-only graph admission and simulation
src/actors.mjs        # Host actor-handler examples + tenant-scoped MemoryLedger
scripts/demo.mjs      # CLI to replay scenarios and inspect traces
tests/                # Node 22 contract and safety regression tests
docs/                 # Mermaid workflow diagrams, pipeline and durability notes
```

## Design decisions

- **Actors are the work units**: in real Oreslang, `define actor` classes receive messages, and a future `Workflow` base actor should supervise them.
- **Graph edges model versioned workflow routing**, but the simulator itself has no durable storage. They are distinct from live actor streams. The proposed `pipe` syntax is not used by the executable JavaScript graph simulator or assumed guest-compilable.
- **Proof must travel with memory**: exact revision, executed CI steps, tenant/repository scope, replay ID, and provenance. The memory handler requires an out-of-band injected verifier and a private grant; the supplied demo verifier is a deterministic **test fixture**, not an authenticated GitHub API or signed CI check.
- **No fake durability or exactly-once claims**: the simulator uses process-local memory. Production requires storage transactions, fenced epochs, authenticated ingress, idempotent outbox delivery, redaction and migration.
- **Private-source safety**: do not mirror private Oreslang Git trees to other organizations without independent authorization. A working Actions runner alone is not export permission.

Upstream references: [durable workflow contract](https://github.com/ores-truffle-oreslang/oreslang-common-source/blob/main/docs/DURABLE_WORKFLOW_ACTORS_V0.md), [host conformance PR #221](https://github.com/ores-truffle-oreslang/oreslang-platform-conformance/pull/221), [Java workflow guest PR #2241](https://github.com/ores-truffle-oreslang/oreslang-source.java/pull/2241), [private-source security incident #22](https://github.com/ores-truffle-oreslang/oreslang-platform-conformance/issues/22).

## Next real-runtime milestone

Compile and run the `.ores` examples with the exact-head Java/Graal toolchain, then move coordination from the host simulator into a real supervisor actor with sealed state. Repeat the same fixtures across LLVM, .NET AOT, WASM and Forge; keep each backend `NOT_EXECUTED` until it actually runs.

## Hardening checks

The graph simulator rejects cyclic or unsafe nested JSON, oversized messages,
nonfinite numbers, and inherited signals. The AI-memory pipeline requires an
out-of-band evidence verifier; a supplied `evidenceVerified:true` property
does not authorize a memory write. The verifier now also binds the trusted
workflow path, numeric workflow ID and required named test job, not just a
user-controlled step name.

**Native Node 22 acceptance is now established for the source-free demo:**
see [exact-blob local report](docs/LOCAL_NODE22_ACCEPTANCE.md). This is not
a hosted Actions run or an Oreslang guest-runtime acceptance.

## Read-only GitHub evidence verification

A CI run ID submitted by an agent is **a lookup key, not proof**. The
`src/github-evidence.mjs` verifier uses a separately configured tenant→repo
policy and a read-only GitHub API adapter to examine the exact run head SHA,
workflow identity, status, attempt, actual job steps and required
`Run Node tests` step. It rejects zero-step jobs and foreign-repository runs.

For an operator with authorized read access to that repository:

```bash
GITHUB_TOKEN=... node scripts/verify-github-run.mjs \
  tenant_a ores-truffle-oreslang/oreslang-step-function-demo \
  RUN_ID ATTEMPT EXACT_HEAD_SHA event_1
```

This is a **GitHub REST metadata check**, not cryptographically signed job
attestation. Keep the token outside repository files and logs. The existing
`npm run demo` still uses a fixed synthetic test verifier, deliberately
not an online GitHub API call.

## Restart-safe developer memory

```bash
npm run demo:durable
# Optionally retain a private local ledger between runs:
node scripts/durable-demo.mjs /secure/local/path/memory.json
```

The `JsonFileMemoryLedger` uses same-directory atomic replace, file/directory
fsync, a versioned SHA-256 checksum, tenant-scoped indexing, bounded records,
replay-conflict detection and deletion. Reopening the ledger simulates a new
agent session retrieving a previously committed fact.

**Important:** This is a **single-writer local-file demonstration**, not a
storage-enforced lease, authenticated snapshot, multi-writer database, or
restartable Oreslang actor. Do not use it for production external effects.
The unexecuted PostgreSQL design sketch is in
[`sql/durable_memory_v1.sql`](sql/durable_memory_v1.sql); real DB
transactions, RLS, crash proof and fencing remain acceptance requirements.

## Execution and evidence status

On an exact-Git-blob local reconstruction using Node.js **v22.16.0**:

- `npm test`: **44/44 tests passed** (23 graph, 10 CI-evidence,
  9 real-filesystem ledger, 2 separate-process restart).
- `npm run verify`: passed for all three graphs.
- `npm run demo`: passed.
- `npm run demo:durable`: passed with one recovered memory record.

These checks used real Node `structuredClone`, `node:crypto`, filesystem
rename/fsync and separate OS processes. This was not a full Git checkout and
is not an independently signed attestation. Exact blob hashes and the
execution scope are in [the report](docs/LOCAL_NODE22_ACCEPTANCE.md).

**Still unverified:** GitHub-hosted CI tests (the source-org jobs currently
fail before steps run), real Java/Graal Oreslang guest compilation,
PostgreSQL storage-enforced fencing, and LLVM/.NET/WASM/Forge parity.

Per-task deadlines and cooperative cancellation bound *simulator waiting*;
external operations may continue after timeout/abort. No physical actor
quiescence or exactly-once external effect is claimed.
