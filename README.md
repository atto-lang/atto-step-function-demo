# AttoLang Step Functions — native actor workflows

**AttoLang is the current language name.** This repository now uses `.atto` for all native guest sources: nine canonical workflow programs plus four actor baselines. The repository and compiler may retain historical `oreslang` identifiers for compatibility.

The nine programs model sequential tasks, conditional routing, two-worker fan-out with an explicit join, fixture-only memory, quarantine, approval gates, bounded retry, cancellation-before-start, and a state-guarded workflow coordinator. JSON graphs are diagrams, **not** a workflow interpreter. No Node.js or Python implementation runs workflow logic.

## Run source-policy and host-only mutation checks

```sh
sh ci/audit-source.sh
sh ci/test-atto-manifest.sh
bash ci/test-native-precompiler-admission-wave31-20261105.sh
bash ci/test-python-source-policy.sh
```

These checks validate the Git-index inventory and fail-closed admission logic. **They do not compile or execute any AttoLang guest.**

## Compile and run real `.atto` guests

The reference Java/GraalVM compiler is developed in [oreslang-source.java](https://github.com/ores-truffle-oreslang/oreslang-source.java) and is **not bundled** here. Provision a trusted compiler binary first; its historical Java launcher class is `dev.oreslang.launcher.OresMain`.

```sh
attolang-compiler --check workflows/order-workflow.atto
attolang-compiler workflows/order-workflow.atto

# Real native acceptance of all nine canonical cases:
ATTOLANG_BIN=/absolute/path/to/attolang-compiler \
ATTOLANG_COMPILER_SHA256=<trusted-64-character-lowercase-sha256> \
EXPECTED_SOURCE_SHA="$(git rev-parse HEAD)" \
sh ci/verify-native.sh
```

Legacy environment variables `ORESLANG_BIN` and `ORESLANG_COMPILER_SHA256` are supported for existing runner provisioning, but disagreeing new and old variables fail closed. The executable must implement `--build-info`, `--check`, and direct `.atto` guest execution.

## Nine exact-output native workflow contracts

| Executable `.atto` source | Exact stdout |
| --- | --- |
| [order-workflow](workflows/order-workflow.atto) | `order:complete` |
| [order-rejected](workflows/order-rejected.atto) | `order:rejected` |
| [agent-memory-workflow](workflows/agent-memory-workflow.atto) | `memory:fixture-indexed` |
| [agent-memory-quarantine](workflows/agent-memory-quarantine.atto) | `memory:quarantined` |
| [release-review-workflow](workflows/release-review-workflow.atto) | `release:preview-only` |
| [release-waiting](workflows/release-waiting.atto) | `release:waiting` |
| [bounded-retry](workflows/bounded-retry.atto) | `retry:complete-after-two` |
| [cancel-before-work](workflows/cancel-before-work.atto) | `cancel:stopped-before-work` |
| [coordinator-state](workflows/coordinator-state.atto) | `workflow:state-guarded` |

Four additional `.atto` actor baselines live in [`examples/attolang/`](examples/attolang/); they are not part of the nine canonical stdout oracles.

## Current AttoLang conventions

- New guest sources use **`.atto`**, never `.ores`. The source policy rejects tracked legacy `.ores` sources.
- Comparison operators use **`eq`** and **`neq`** rather than legacy `==` / `!=`.
- Explicit actor `spawn`, `send`, output-channel `await`, and `get_done()` joins are preserved. Each workflow remains in-memory and bounded; experimental uncompiled language features are not assumed.
- A structural success is not a compiler verdict; only exact-head guest execution against a trusted compiler can establish runtime results.

## Evidence limits

**The migrated `.atto` programs have not been proven to compile or execute until the native job runs with nonzero executed steps and a trusted compiler binary.** The verifier demands a clean exact Git head, a compiler digest, bounds on guest execution, all nine distinct source/output checks, and byte-for-byte stdout.

These programs are not a durable Step Functions replacement: no authenticated identities, production approval, persistent checkpoints, transactionally atomic inbox/outbox, crash recovery, real payment, external publish, or guaranteed exactly-once effects. Memory indexing and review approval use fixed local fixtures and confer no privileges. A SHA-256 of a compiler executable is not, alone, an attestation of its compiler source tree.

See [`.atto` migration and parity gates](docs/ATTO_MIGRATION.md), [implementation boundaries](docs/BOUNDARIES.md) and [workflow diagrams](docs/GRAPHS.md). The older dated audit notes describe historical `.ores`-era evidence and must not be cited as acceptance of these renamed sources.
