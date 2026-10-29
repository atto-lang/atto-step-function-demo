# Required GitHub main-branch protection — NOT YET ENABLED

**Observed on 2026-10-29:** GitHub returned `protected: false`,
`required_status_checks.enforcement_level: off`, and an empty check list for
`ores-truffle-oreslang/oreslang-step-function-demo` `main`.
The connected GitHub integration returned HTTP 403 on the branch protection API.
Adding a CODEOWNERS file or writing this document does **not** enable protection.

## Repository administrator steps

1. Configure an active branch ruleset targeting `refs/heads/main` with
   enforced required pull requests, at least one independent approval,
   **require review from Code Owners**, dismiss stale approvals, and forbid
   force pushes and bypass by ordinary maintainers.
2. Require the exact-head check `native-guest-execution` from the
   `Native Oreslang workflows` workflow, plus `native-source-policy`.
   Job **conclusions alone are insufficient evidence**: audit the job steps
   and reject empty/null step lists or missing runner allocation. Because
   source-org Actions is currently returning zero-step failures, do **not**
   weaken the required checks merely to get a green merge.
3. Require a trusted compiler executable that really compiles/runs guest
   `.ores`, with pinned SHA-256 and source provenance. A checked-in wrapper,
   a mock, Node.js, a synthetic carrier canary, or a source-only match is
   not native proof.
4. Keep cross-organization private-source copies prohibited until the
   independent incident owner explicitly resolves
   [platform-conformance issue #22](https://github.com/ores-truffle-oreslang/oreslang-platform-conformance/issues/22)
   and the protected incident registry authorizes the destination.
   **Verified private visibility alone is not authorization.**
5. Avoid premature merge of draft PRs. Review the pre-execution merge incident
   [demo issue #8](https://github.com/ores-truffle-oreslang/oreslang-step-function-demo/issues/8).

## Currently available native compiler gate

A targeted **same-org private** compiler branch implements JUnit guest
execution of the *nine exact-byte* demo fixtures, in addition to three
pre-existing actor-step examples:

- Java/Graal PR [#2241](https://github.com/ores-truffle-oreslang/oreslang-source.java/pull/2241)
- Compiler source head: `6123cbe890ae79a7eca12ddcdaa490f724f31930`
- Demo source head copied for test: `0ba32f019a0c1dfcf9aaa2f91accb030178f5a45`
- Workflow: `.github/workflows/actor-demo-native-guest.yml`
- Test: `SourceActorDemoWorkflowExecutionTest`, using actual
  `Context.eval(Source.newBuilder(OresLanguage.ID, ...))` and pinned
  Git-blob checks. It is not a Java host simulator.

**Status: TESTS ADDED; NOT_EXECUTED.** A GitHub Actions run with zero recorded
steps is an infrastructure failure, never a guest compilation failure or pass.

## Validation before changing this document

Repository admin must independently verify the effective branch ruleset and
check name/status on the latest SHA via GitHub's authenticated API/UI. An
unenforced CODEOWNERS file must not be cited as effective merge protection.
