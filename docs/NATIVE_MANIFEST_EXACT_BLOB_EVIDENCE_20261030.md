# Exact-blob native manifest admission: source-only test record (2026-10-30)

**Status: 1 positive and 12 negative LOCAL SOURCE-ONLY TESTS PASSED. This does NOT establish compiler, actor guest, AOT, persistent saga, or cross-backend runtime execution.**

## Immutable code checkpoint

- Source repo: `ores-truffle-oreslang/oreslang-step-function-demo`
- Native manifest hardening code commit: `e470c6ddbde515832128bfe3ddbdf45cc6aff511`
- Code Git root tree: `52ac723e0a6c93fcc91688c8f09da853b8aada89`
- Exact `ci/check-native-manifest.sh` Git blob: `ce390a81fde63a15b800f29212613a585f941794`
- Added committed selftest source: `ci/test-native-manifest.sh` Git blob `7ee717183ef50f940c8cd3132e2cabf7d8292701`
- No production compiler binary or private source mirror was used.

## Independent local execution

The manifest checker was reconstructed from its exact GitHub file bytes inside a fresh, synthetic local Git repository. `git hash-object` matched the committed checker blob before the tests. Fourteen synthetic `.ores` placeholders (not actual Oreslang workflow sources) were tracked with the canonical fourteen manifest paths and distinct stdout oracles.

The exact checker admitted the valid 14/14 source inventory and rejected **12/12** synthetic adversarial cases, with diagnostics asserted for each: missing manifest entry, duplicate path, duplicate stdout, duplicate dash-prefixed stdout, path traversal, invalid stdout delimiter, symlinked guest, unlisted guest, dirty guest, skip-worktree-hidden manifest mutation, skip-worktree-hidden guest mutation, and assume-unchanged-hidden guest mutation.

The local driver checked the actual `ci/check-native-manifest.sh` implementation, **not** the full committed `ci/test-native-manifest.sh` or `ci/verify-native.sh` executions. It is intentionally narrower than the complete GitHub source-policy workflow.

## Security improvement

A clean `git status` is insufficient evidence of exact source bytes: `git update-index --skip-worktree` and `--assume-unchanged` can make dirty files invisible to normal status. The checker now compares `git hash-object` of both the manifest and each guest source with `git rev-parse HEAD:path`. The duplicate oracle comparison uses `grep -Fxq --`, so a leading `-` is not parsed as a flag.

The committed `ci/test-native-manifest.sh` now declares twelve negative cases, while the full `ci/verify-native.sh` still requires a trusted compiler binary and SHA-256, real guest execution and stdout oracle checks.

## Integration and governance

All fourteen real Step Functions source Git blobs remain identical to the fourteen Java/Graal guest resources at Java PR #2246 code head `3f088da096bfdfb7f8f18d6084c15894adf7cd1a`; that is source identity only.

Alternate-org Beamscale source-free run [#41008869494](https://github.com/beamscale/bmscl-compiler/actions/runs/41008869494) executed successfully with no checkout. Cross-org export remains **NOT AUTHORIZED** under conformance security incident #22, unprotected source/carrier main branches, and independent review requirements. Private source was not transferred.

**Release gate remains open:** execute the full native source policy and fourteen `.ores` cases, the Java four baseline guests, compiler and isolated-actor negative cases, obtain executed steps and provenance artifacts, and secure independent review/protected-main enforcement. Keep PR #11 in draft.
