# Oreslang Step Functions — actors, graphs and AI-agent memory

A hands-on **actor-first workflow demo** for [Oreslang](https://github.com/ores-truffle-oreslang/oreslang-source.java). Includes three declarative DAGs, a source-free JavaScript graph simulator and tests, and Oreslang `.ores` actor-message examples.

> **Execution status:** The JavaScript code is a **host-only simulator**, not an Oreslang runtime or durable workflow engine. The Oreslang examples follow the Java/Graal source-actor baseline in [Java draft PR #2241](https://github.com/ores-truffle-oreslang/oreslang-source.java/pull/2241); actual guest execution is not yet independently verified. No API credentials, network writes, authenticated approvals or production persistence are implemented.

## Try the demos

Install **Node.js 22+**; no npm dependencies are needed.

```bash
npm test
npm run verify
npm run demo
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

The workflow graph runtime rejects cyclic/class-instance/unsafe nested JSON,
non-finite numbers, oversize messages and responses, and inherited-property
approval signals. The memory pipeline fails closed when no independent
`evidenceVerifier` is configured or the verifier fails/mismatches. Client
fields such as `evidenceVerified:true` cannot authorize `remember_fact`.

**18/18 targeted checks passed** in an isolated strict-mode JavaScript evaluator
of the exact PR source blobs with explicit JSON clone, UTF-8 size and graph
loading shims. An unmodified Node 22 test run and actual `.ores` guest
execution are still required for authoritative acceptance.
