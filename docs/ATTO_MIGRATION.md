# AttoLang `.atto` workflow migration — verification contract

Migration is based on demo `main` commit `a177e84bd84da8b070d3117a6b89b0a9bf5583fa`. Reference Java/GraalVM `main` was observed at `6d8eb70048eafc9a84c5aebe9c1bb06104f16e76` on 2026-11-10; this is **not** proof that any compiler executable was built from that SHA.

## Compatibility boundary

All nine `workflows/*.atto` and four `examples/attolang/*.atto` files are canonical. The previous `.ores` blob history is retained in Git, but no `.ores` guest remains in the current tree. Language comparisons now use `eq` and `neq`; actor protocol and nine byte-for-byte stdout oracles are preserved. The repo name and historical compiler environment variables remain compatible for migration. We do **not** assume experimental `define isolated actor`, durable `state` containers, authenticated storage ports, or full actor-heap isolation have landed.

## Acceptance gates

| Gate | Required execution evidence | Scope |
| --- | --- | --- |
| Source inventory | `sh ci/audit-source.sh` plus 10 negative manifest mutation tests | Tracked `.atto` paths, exact oracles, symlink/mode/traversal/legacy rejection, **host only** |
| Compiler admission | Five negative precompiler tests and exact binary SHA-256 | Refuse missing/mismatched identity, **not guest execution** |
| Java/GraalVM guest | `--check` and bounded real run for all nine `.atto` sources with exact stdout | Actual language/runtime behavior, only on tested source/compiler SHA |
| LLVM, .NET NativeAOT, Wasm, Forge | Independently execute same exact `.atto` source/head with backend-specific trusted compiler | Backend parity only after real guest execution |
| Durability | Crash/restart/CAS, authenticated adapter, effect reconciliation, idempotency and failover tests | **Not implemented by these nine in-memory demos** |

The native gate must report source head SHA, each source blob SHA, compiler executable SHA-256, expected stdout, actual byte-for-byte output, and zero/nonzero process exit. CI jobs must have nonzero recorded steps, and source-to-binary provenance must be established by trusted build receipts beyond a hash of a wrapper.

## Highest-priority next code and test work

1. Build/provision a genuine AttoLang compiler with `.atto`, `eq`, `neq` and actor output support; pin its source revision, executable hash and provenance receipt.
2. Execute the nine native cases on exact demo PR head; fix genuine compiler failures upstream without weakening expected output, and verify all workflow branches terminate.
3. Add compiler-negative fixtures for forbidden in-actor `receive`, unsafe state borrowing, invalid message types, missing join results, stale generation and invalid namespace resolution. Keep compile-error tests separate from runtime stdout oracles.
4. Extend real actor coverage for join failure, cancellation after work starts, deadlines, retry exhaustion, supervisor restart, backpressure and resource limits.
5. Reconcile separate durable-workflow draft PRs (#11, #19, #23–#29) after their SQL, source/identity admission and independently reviewed evidence; do not imply durable execution from fixed-string fixture tests.

Alternate-organization CI for private source requires separate authorization, exact tree/blob identity checks and destination-owned runner credentials. A zero-step job (`steps=[]` or `null`) is runner non-admission, not a passing compiler test.
