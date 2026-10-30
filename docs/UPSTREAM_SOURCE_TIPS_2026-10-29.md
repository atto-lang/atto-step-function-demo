# Upstream source tips and native acceptance — 2026-10-29

Repository: `ores-truffle-oreslang/oreslang-step-function-demo`. **Audit only; no compiler/runtime pass claimed.**

## Default-branch finding

The earlier main baseline has nine workflow guest programs, while draft integration PR #11 contains fourteen native workflows and a fail-closed harness. The native execution workflow depends on separately provisioned ORESLANG_BIN and compiler SHA-256; this audit has not observed a successful exact-head compiler run.

## Source contracts and hardening priorities

- Oreslang Java reference `main` observed at commit `9f4f4a3b75dd4b124e8509b65a88a98213c11ab5` prohibits Python tooling throughout the organization; port existing Python tests/tools to Rust without deleting test coverage.
- Require actor-owned, bounded resources; immutable/sendable mailbox values; sealed state and supervisor-only panic notices; deny-by-default permissions, identity-bound host effects and fail-closed errors. Avoid unmerged syntax/features unless they are tied to an exact branch and compiler test.
- Use `snake_case` methods and admitted `rt borrow`, `rt take`, `rt copy`, `rt share` operations. Blocking I/O should not silently block actor execution; ensure explicit capability grants and request/response bounds.
- Java/GraalVM, LLVM, WASM, .NET and Forge require independent source/runtime/compiler pins and executable semantic oracles for parity.
- Source-org runner exhaustion **does not authorize** private-source export: carrier transfers require separate approval, exact source-tree/blob binding and no secret reuse. A run with `runner_id=0` or zero recorded steps is `NOT_EXECUTED`.

## First executable gate

Execute all native workflows against one vetted compiler with exact SHA-256/--build-info and stdout/exit oracles, include sealed-state coordinator and effect ledger branches, and require runner steps and protected-main checks.

**Existing work:** PRs #7, #10 and #11 already contain native workflow, sealed actor state and ledger work; do not merge on zero-step CI.

## Promotion gate

Capture the exact demo commit/tree, compiler source/build SHA-256, environment and runner ID; check all guests with a real compiler; execute bounded positive and negative wire/actor cases with exact output and exit comparison. Structural CI, mock tests and compiler/guest runs are separate statuses. No merge or portability claim without independent review and latest-head required checks.
