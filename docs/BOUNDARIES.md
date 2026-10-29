# Implementation boundaries — Oreslang only

## Language of the actual demo

The implementation in this repository is **Oreslang**:
- `src/order_workflow.ores`: actor validation, routing and parallel fork/join.
- `src/saga_workflow.ores`: actor checkout and reverse-order compensation.
- `src/memory_pipeline.ores`: capture, fail-closed evidence gate and quarantine.
- `src/review_workflow.ores`: release preparation and unauthenticated WAITING.
- `src/step_graph.ores`: Oreslang transition functions.

There are **no JavaScript implementations under `src/`**.

The previous Node.js graph simulator, actor handlers, saga simulator,
GitHub metadata verifier and JSON file ledger have been moved to
`tests/reference/`. They are **test reference implementations**, not
runtime components of the Oreslang application. All Node.js test runner and
demo scripts are under `tests/tools/`. The JSON graphs under `graphs/`
are test vectors / diagrams, not the authoritative Oreslang implementation.

## Real capabilities and limitations

The order and saga examples are Oreslang actor programs patterned on the
Java/Graal source fixture baseline: `define actor`, `receive(ActorMail<String>)`,
`await spawn`, `send`, `outputs.next` and `get_done`.
They implement actor message chains, decision routes, parallel work and
acknowledged business-event compensation **in source**.

The current memory and review Oreslang actors deliberately **fail closed**
until native authenticated CI/run evidence, human approval and durable
transactional storage exist. The prior Node.js CI verifier and local JSON
ledger are not substitutes for Oreslang native APIs.

The Oreslang sources have **NOT** been successfully compiled/executed against
an exact-head Oreslang guest runtime in this PR. Java/Graal, LLVM, .NET AOT,
WASM and Forge remain `NOT_EXECUTED` until real compiler, runtime and
conformance outputs exist.

Node tests inspect source file placement and compare model semantics. They
do **not** validate parser/typecheck/lowering/runtime compatibility. A passing
Node test suite must never be represented as an Oreslang execution pass.

The generic durable coordinator, sealed state loans, source-language
verification capability, supervisor CONTROL notices, retries/cancellation,
storage-fenced inbox/state/outbox and crash recovery are separate
implementation/acceptance work. The proposed SQL schema is unexecuted.

## CI and release controls

The source organization currently reports GitHub Actions jobs that fail
before any steps execute. This is an infrastructure blockage, not an Oreslang
compiler verdict. Private-source transfer to another GitHub org remains
forbidden while [P0 incident #22](https://github.com/ores-truffle-oreslang/oreslang-platform-conformance/issues/22)
requires independent approval. No private-source cross-org mirror should be
used to bypass this incident.

**Do not merge PR #1 until the actual Oreslang source is compiled,
executed and independently reviewed.** The connector did not permit changing
PR #1 back to draft, so the PR title and description explicitly mark this
restriction.

## Historical reference reports

`LOCAL_NODE22_ACCEPTANCE.md` and `SECURE_CI_AUDIT_20261028.md`
describe tests of the **former JavaScript reference model**. Those test
results remain useful for the test oracle, but are not production-language
execution results.
