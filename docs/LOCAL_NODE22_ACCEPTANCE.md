# Node.js 22 native acceptance — local, exact Git blob evidence

**Classification:** local source-free host-model execution; **not** GitHub-hosted CI, signed CI attestation, PostgreSQL durability, or compiled Oreslang actor guest execution.

- **Tested PR head before this documentation commit:** `e4c11c87e2cadd41066f9e605a6343c78fbd7eee`
- **Runtime:** Node.js `v22.16.0` and npm `10.9.2` in the local container (Linux).
- **Reconstruction:** privately fetched GitHub source, tests, graphs and scripts re-created locally. Every file in the table below was checked using `git hash-object` and its exact GitHub blob SHA. This is an exact-blob subset of the repository, not an independently authenticated Git checkout.
- **Native test command:** `npm test` → **44 tests, 44 pass, 0 fail**, real `node:test`, `structuredClone`, timers, SHA-256, real filesystem rename and fsync.
- **Other native commands:** `npm run verify` → PASS (3 graphs); `npm run demo` → exit 0; `npm run demo:durable` → exit 0 and `stored:1`.
- **Suite breakdown:** 23 graph/actor workflow tests + 10 CI-evidence-reader fixture tests + 9 real filesystem ledger tests + 2 **real separate-process** memory recovery tests.
- **CI truth:** source-org Actions [40818058236](https://github.com/ores-truffle-oreslang/oreslang-step-function-demo/actions/runs/40818058236) and [40818051464](https://github.com/ores-truffle-oreslang/oreslang-step-function-demo/actions/runs/40818051464) still FAILED before running job steps (`steps=null`). Those failures are infrastructure/admission evidence and cannot be called test execution.
- **Security:** no cross-organization source mirror performed; [incident #22](https://github.com/ores-truffle-oreslang/oreslang-platform-conformance/issues/22) remains open and requires independent approval before source transfer.
- **Missing gates:** hosted real-steps CI; compiled Java/Graal `.ores` actor fixture; PostgreSQL storage-enforced fencing, tenant RLS and transactional inbox/outbox; LLVM/.NET/WASM/Forge guest parity. A successful local host-only model test proves none of these.

## Verified exact Git blobs

| Path | Git blob SHA-1 |
|---|---|
| `package.json` | `35a3f9e34eb26c6cb2ec15e9a728acfbb901784f` |
| `graphs/agent-memory-pipeline.json` | `8cb44295b522e3b9c64c79a3eb89f75fe2651ff5` |
| `graphs/order-pipeline.json` | `f426623aa692d7052feb275254004219ba42ab27` |
| `graphs/release-review-pipeline.json` | `8e4266480527306a29ef3d7b3cbd37f3caf8c73b` |
| `scripts/demo.mjs` | `d11590ffd0ffd645d5079167fd0c801d3fd302ac` |
| `scripts/durable-demo.mjs` | `3d52b76c0634da7a9f5f4a6d608d180a43469bf8` |
| `scripts/recall-memory.mjs` | `af73b6bf1543e1366150bfa749af482b9bd51629` |
| `src/actors.mjs` | `38d8c5433e6b799c7250ea2543a4670bea54ab4a` |
| `src/durable-memory.mjs` | `a353b80f2c2e384f9e9440ffa31ead4539226545` |
| `src/github-evidence.mjs` | `f3cc72a5072231fae03769c03e1c0a49f322f063` |
| `src/graph-runtime.mjs` | `ea775527b91f591b089c9b65f7031f70e4376cd2` |
| `tests/durable-memory.test.mjs` | `d9b77381fb9aaa4c62d77dd831749f9e2691cc54` |
| `tests/github-evidence.test.mjs` | `240a6eff22fd61768997917c30d27735f9a9a139` |
| `tests/graph-demo.test.mjs` | `8c0e3afc0f9cf9a187d0c39dfcee79004738a15a` |
| `tests/process-restart.test.mjs` | `ae18dcc85471dc9776a2dc73414ccce12a25e70c` |
| `tests/storage-process-smoke.test.mjs` | `3808b87ed3a0a02169d62a5d20d6f4cb0835181b` |

The report is **not a signed attestation** and does not establish independent verification of the runner environment. The test runner's raw TAP output and demo logs were retained in the local container during verification.

