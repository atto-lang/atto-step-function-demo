# Oreslang Step Functions — native actor workflows

**This repository's workflow implementation is written in Oreslang (.ores). There is no Node.js simulator, JavaScript step engine, npm package, or JavaScript actor-handler implementation.**

Twelve native Oreslang programs demonstrate sequential tasks, conditional routing, parallel actor fan-out/join, fixture-scoped agent memory, quarantine on invalid input, and preview-only review gates. All *execution* and *coordination* shown in these programs occurs in Oreslang. Non-Oreslang files are static graph diagrams, documentation, and a shell test runner.

## Execute native Oreslang

Use an Oreslang compiler/runtime that supports the native actor guest syntax. The Java/Graal reference backend provides a CLI entry point `dev.oreslang.launcher.OresMain`; its CLI takes a source file directly and supports `--check` for validation. The executable must be built/provisioned separately. **The compiler is not bundled in this repository.**

```sh
oreslang-compiler --check workflows/order-workflow.ores
oreslang-compiler workflows/order-workflow.ores

# Run all twelve native guest scenarios against an installed compiler:
ORESLANG_BIN=/absolute/path/to/oreslang-compiler sh ci/verify-native.sh
```

Expected output for the complete order scenario: `order:complete`. The native-only verification script fails if the compiler is missing; it never falls back to Node.js, JavaScript or a host simulator.

## Native Oreslang workflows

| Executable Oreslang source | Graph semantics | Expected result |
| --- | --- | --- |
| [order-workflow.ores](workflows/order-workflow.ores) | Validate → branch → inventory/payment actors concurrently → explicit join | `order:complete` |
| [order-rejected.ores](workflows/order-rejected.ores) | Reject bad input before spawning downstream actors | `order:rejected` |
| [agent-memory-workflow.ores](workflows/agent-memory-workflow.ores) | Capture → fixture verification → conditional ephemeral index | `memory:fixture-indexed` |
| [agent-memory-quarantine.ores](workflows/agent-memory-quarantine.ores) | Quarantine unverified input without indexing | `memory:quarantined` |
| [release-review-workflow.ores](workflows/release-review-workflow.ores) | Prepare → test-fixture review → preview-only actor | `release:preview-only` |
| [release-waiting.ores](workflows/release-waiting.ores) | Await human approval; do not invoke a publishing actor | `release:waiting` |
| [bounded-retry.ores](workflows/bounded-retry.ores) | At most two distinct actor attempts; explicit stop condition | `retry:complete-after-two` |
| [cancel-before-work.ores](workflows/cancel-before-work.ores) | Cancellation gate terminates before spawning downstream actors | `cancel:stopped-before-work` |
| [coordinator-state.ores](workflows/coordinator-state.ores) | Stateful workflow actor refuses out-of-order, foreign and duplicate events | `workflow:state-guarded` |
| [order-saga-success.ores](workflows/order-saga-success.ores) | Native saga: inventory → payment → shipment | `saga:complete` |
| [order-saga-compensated.ores](workflows/order-saga-compensated.ores) | Known no-effect shipping rejection → reverse compensators | `saga:compensated` |
| [order-saga-ambiguous.ores](workflows/order-saga-ambiguous.ores) | Unknown shipment outcome → stop, no automatic compensation | `saga:reconciliation-required` |

The `graphs/*.json` files are **design diagrams only**, not an alternate JavaScript execution format. They are *not* interpreted by a host-language workflow engine. Native graph topology is expressed by actor spawning, message passing, routing, and joining inside each `.ores` source.

Older actor examples in `examples/oreslang/` remain as small upstream-compatible guest syntax baselines. They are also Oreslang.

## Guarantees and limitations

These are in-memory actor guest demos, **not** durable Step Functions yet. In particular:

- There is no persistent Workflow actor, checkpoint/restart protocol, transactional outbox, fencing epoch, or storage-atomic inbox consumption.
- The memory and approval paths use **fixed local fixtures**, not authenticated GitHub run evidence, a real identity provider, a database, or production-grade authorization. No real writes, publishes, or deployments occur.
- No unbounded retry loop, silently flattened nested Future, implicit actor reentrancy, or host-language graph execution is required.
- This branch has **not yet demonstrated a real compiler-backed execution** of these twelve new sources; until a job actually executes guest steps, all native runtime outcomes remain `NOT_EXECUTED`. A source-policy GitHub Action is not a compiler test.
- Do not mirror private repository code to an alternate organization without the separately required approval.

The durable semantic target is [Durable Workflow Actors v0](https://github.com/ores-truffle-oreslang/oreslang-common-source/blob/main/docs/DURABLE_WORKFLOW_ACTORS_V0.md). The independent Java/Graal upstream source-actor test is [oreslang-source.java PR #2241](https://github.com/ores-truffle-oreslang/oreslang-source.java/pull/2241), which is a different tree and is **not** evidence that this repository's twelve new programs have executed.

## Architectural next steps

1. Compile/run each `.ores` source at the exact demo SHA and record compiler SHA, exit code, expected output, and actual executed test steps.
2. Implement a true **native Oreslang Workflow actor** with sealed state, explicit supervisor, versioned typed graph nodes, ownership/cancellation, bounded retries, and versioned messages.
3. Add an Oreslang durable workflow library that checkpoints using backend-provided bounded storage primitives. A Java or C# platform adapter may implement primitive I/O, but may not implement workflow semantics.
4. Extend the same native `.ores` fixture suite across LLVM, JVM/Graal, Wasm and .NET, withholding parity claims until actual guest code runs.

The previous Node.js implementation was merged by [PR #1](https://github.com/ores-truffle-oreslang/oreslang-step-function-demo/pull/1). It has been removed from the executable demo in this corrective branch, not silently retained as a second workflow engine. Historical review records remain in Git history.


## Test and supply-chain policy

`sh ci/audit-source.sh` is a **static policy check**, not execution evidence.

`ci/verify-native.sh` checks an exact clean Git checkout and requires
`ORESLANG_BIN` (absolute path to a real compiler executable) plus
`ORESLANG_COMPILER_SHA256` (64-character lowercase SHA-256 of that executable).
It uses `--build-info`, compiler `--check`, a bounded guest execution and
byte-for-byte stdout assertions for **all twelve** `.ores` sources. Missing
compiler, wrong digest, timed-out guest, a missing test case, dirty source,
or changed source SHA fails closed. A digest pin is not a signed build
attestation: independently establish which compiler source revision produced
the pinned executable.

On a GitHub Actions PR the checkout uses the actual PR head SHA rather than
the synthetic PR merge ref. Repository variables `ORESLANG_BIN` and
`ORESLANG_COMPILER_SHA256` are required by the native guest job. A normal
hosted runner does **not** include a prebuilt Oreslang compiler. Provision the
binary through a separately authorized build/deployment workflow; do not
mirror private source to another org or assume `GITHUB_TOKEN` can check out
another private repository.

The old Node-only acceptance reports in `docs/` are **historical and
inapplicable** to this native branch. A successful source-policy check,
or a GitHub Actions failure with zero recorded job steps, cannot establish
guest execution.

## Native checkout saga

Three source-guest `.ores` programs exercise success, LIFO reverse compensation for a **known pre-effect business rejection**, and fail-closed reconciliation for an unknown shipment outcome. They use only fixed actor-message fixtures; no real payments or external effects. See [native saga contract](docs/SAGA_NATIVE.md) and the [isolated durable coordinator design](docs/WORKFLOW_COORDINATOR_V0.md). `graphs/order-saga.json` is **documentation-only** and is not executed as an alternate workflow engine.
