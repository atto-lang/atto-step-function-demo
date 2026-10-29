# Workflow hardening and CI provenance audit — 2026-10-28

## Result: source-free host model

Local runtime: **Node.js 22.16.0**, native `node:test`, real filesystem/SHA-256 and separate OS processes. This was a **local reconstructed checkout from exact private GitHub blob content**, not GitHub-hosted CI and not actual Oreslang guest execution.

- `npm test`: **58/58 passed**, 0 failed, 0 skipped.
- Suite breakdown: **34 graph/actor + 12 independently-fetched GitHub-evidence fixture + 10 real filesystem + 2 separate-process memory recovery**.
- `npm run verify`, `npm run demo`, `npm run demo:durable`: all exit 0.
- Runtime fix at commit `820d7c6dbf2ddeaedd537c5c434690f38509dcde`: a user actor's ordinary `Error('WORKFLOW_CANCELLED')` or `Error('TASK_TIMEOUT')` can no longer forge scheduler cancellation or deadline evidence; exact **private Symbol sentinel identity** is checked instead.
- Regression fix at commit `8548844d41813ab1d8b6c754f443a45cc69269d8`: two tests cover forged status strings and a cancellation occurring as the listener is installed.
- Earlier behavior was reproduced locally: a thrown `Error('WORKFLOW_CANCELLED')` incorrectly reported `CANCELLED` with no abort requested; `Error('TASK_TIMEOUT')` was misreported as a scheduler timeout. After the patch, both are task failures with result `error`.

## Exact Git blob equality

GitHub files at PR head `8548844d41813ab1d8b6c754f443a45cc69269d8` were reconstructed locally and these `git hash-object` values matched GitHub:

| Path | Git object SHA-1 |
|---|---|
| `src/graph-runtime.mjs` | `1b376b7abe42c0038f9ade3858041ead001edf8c` |
| `src/actors.mjs` | `c9a1edf7f71b8289a9e22f59b8f72095103a0556` |
| `src/durable-memory.mjs` | `44dc7705070c05ae1af6b58151ffc419e201bd0d` |
| `src/github-evidence.mjs` | `4e602d30056b8298117ba8efd39322dd397f0a40` |
| `tests/graph-demo.test.mjs` | `c7418f482034d63dc0170a8321eb593101ff5b1a` |
| `tests/github-evidence.test.mjs` | `161349bd89200be4343b4200730f6d10c83c83ec` |
| `tests/durable-memory.test.mjs` | `ec823817d131fae49b03cb7b4956b6f05133e91d` |

Previously validated unchanged graph, package, demo and process-restart files were reused locally. This is exact-source **subset** reconstruction, not a new authenticated full checkout.

## GitHub Actions source runner admission

Exact-head source-org run [40819920879](https://github.com/ores-truffle-oreslang/oreslang-step-function-demo/actions/runs/40819920879) completed FAILURE, with `node-contract.steps=null`, **zero source/test execution**. Thus it is neither a source-code test failure nor a hosted test pass.

Independent **source-free canary** in private `honeypot-r-us-test/hnpt-lib-core`: [40820027359](https://github.com/honeypot-r-us-test/hnpt-lib-core/actions/runs/40820027359) completed SUCCESS with actual setup, runner-execution, and completion steps. This establishes **runner admission for that canary only**. It does not prove an organization-wide remaining minutes/budget allocation, nor authorize private Oreslang source transfer.

## Cross-organization confidentiality gate — BLOCKED

[Platform-conformance P0 incident #22](https://github.com/ores-truffle-oreslang/oreslang-platform-conformance/issues/22) remains **OPEN** and explicitly states **private-source export remains forbidden** pending containment, audit, destination visibility/provenance and **independent approval**. Even a private alternate destination and token-free `GITHUB_TOKEN` mirroring **do not** override that gate. No private Oreslang Git tree was mirrored across organizations in this audit.

The permitted alternatives are source-org Actions when runner admission is restored, a local authorized exact-blob run, or independently authored **source-free** canaries in other organizations. Never upload private source, exact blob copies, test artifacts containing proprietary code, or source-derived cache to an alternate GitHub organization without explicit clearance.

## Open acceptance gates

- [x] Local Node 22 native runtime regression and memory restart suite, 58/58.
- [x] Fix forged scheduler cancellation/deadline classification.
- [x] Inspect source-org exact-head pre-step CI failure and source-free alternate runner canary.
- [ ] Source-organization Actions actual executed steps on the exact PR head.
- [ ] Independent confidential-source cross-org transfer approval, if a mirror is ever needed.
- [ ] Actual Java/Graal Oreslang source guest fixture compilation and execution.
- [ ] PostgreSQL transactional inbox/outbox, storage-epoch fencing, authenticated ingestion.
- [ ] LLVM, WASM, .NET and Forge guest parity.

All unverified capabilities remain unclaimed. Keep PR #1 DRAFT.
