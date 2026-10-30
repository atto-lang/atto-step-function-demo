# Private alternate-org actor CI — admission-only checkpoint (2026-10-30)

**HOLD: no private source transfer or mirror is authorized.** This document
records the user-requested alternate-org testing technique and a successful
**source-free** runner admission test. It is not authorization to copy any
private source object, invoke a compiler on it, or merge this PR.

## Verified snapshots

| Item | Verified identity |
| --- | --- |
| Private source repository | `ores-truffle-oreslang/oreslang-step-function-demo` |
| Source **code** checkpoint / manifest hardening commit | `90caef01f6c6a51673ea1d8bd66c1e60e9ed13e8` |
| Source code root Git tree | `ccc80bec33d34d615d6c624940098249b3c4b564` |
| Source integration | 14 `.ores` cases with unique expected stdout oracles |
| Candidate carrier | `beamscale/bmscl-compiler`, **PRIVATE** |
| Immutable carrier repository ID | `1383937120` |
| Carrier source-free canary branch | `ci/source-free-actor-runner-admission-20261030` |
| Source-free canary commit | `212a88974ec58e62fd6917d3d89424d96fc11dfe` |
| Canary workflow run | [41008869494](https://github.com/beamscale/bmscl-compiler/actions/runs/41008869494), attempt 1 |
| Canary result | Completed **success**, 3 job steps including the executable Bash step |
| Source transfer | **NONE** |

The source-free canary has `permissions: {}`, no checkout, no secrets,
no cross-org `GITHUB_TOKEN`, and executes only runner-ref and run-identity
assertions. This confirms runner admission at the tested time; **it does not
reveal remaining billed minutes or provide ongoing capacity assurance**.

## P0 security/governance HOLD

The following were checked but **not satisfied**:

1. The source `main` and the carrier `main` both report
   `protected=false`. Enforce effective private branch rulesets and
   issuer-bound mandatory CI on both before considering source transfer.
2. P0 conformance security incident [#22](https://github.com/ores-truffle-oreslang/oreslang-platform-conformance/issues/22)
   remains open, with related incidents [#77](https://github.com/ores-truffle-oreslang/oreslang-platform-conformance/issues/77),
   [#212](https://github.com/ores-truffle-oreslang/oreslang-platform-conformance/issues/212)
   and [#222](https://github.com/ores-truffle-oreslang/oreslang-platform-conformance/issues/222).
3. There is no verified source-owner/security approval binding this
   exact source SHA/tree, destination immutable repo ID, reviewed file allowlist,
   sanitized workflow, execution scope, retention/deletion, and writer identity.
4. No independent security reviewer has approved the transfer. The
   org-wide bootstrap issue [#69](https://github.com/ores-truffle-oreslang/oreslang-platform-conformance/issues/69)
   excludes operator-controlled `ORESoftware` and `the1mills` from satisfying
   the independent review gate; a review request is **not** an approval.
5. The successful canary proves only one source-free runner, not a funded
   full Java/GraalVM native-image build at the actual test time.

**No mirror branch containing private Oreslang source was created.**
Do not use the carrier's `GITHUB_TOKEN` to check out the private source.
Do not copy the source tree as a workaround until the above independent
authorization exists.

## Conditions for an approved future exact-tree mirror

After protection and independent source/destination approval are verified,
snapshot the latest source SHA and exact root-tree SHA (and per-file
blob identities) again. Permit only the approved source file allowlist,
exclude secrets and dangerous source-owned privileged workflows,
write to an isolated, non-default temporary branch in the verified-private
destination through the authorized connector, and compare the
**destination root tree to the approved source tree** before running
any compiler. A partial tree copy must be called a subset test and cannot
be represented as an exact-tree match. Use trusted destination-owned
workflows, least privilege, no cross-org checkout tokens, and no unreviewed
source-provided executable hooks. Capture immutable run ID/attempt, actual
step logs, compiler provenance/SHA-256, expected 14+4 native guest
outputs/negative tests, and test results. Delete temporary refs and
audit for retained artifacts/caches/history under the approved retention
and incident-control procedure.

## Source-local hardening and independent test evidence

On the source code checkpoint, `ci/check-native-manifest.sh`
(blob `4cdc71effd5be9c08c7849db29280fed6394b602`) now rejects
duplicate stdout oracles, in addition to duplicate paths and
missing/untracked/symlinked/dirty native sources. The standalone
`ci/verify-native.sh` (blob `e58b2effa0131295d34ee81329cb1028408773ab`)
now executes the manifest gate before admitting any compiler. The
`ci/test-native-manifest.sh` source (blob
`030cbcd47be8c1ed3e94122b58ad559a77d5c16f`) declares nine
negative tests including duplicate stdout oracles.

**Actual local execution:** the exact Git blob of the updated
`check-native-manifest.sh` was independently reconstructed and
hash-verified, then executed in a separate synthetic Git checkout.
One valid fourteen-case manifest was accepted; eight negative cases
were rejected (duplicate stdout, duplicate path, missing case,
traversal, invalid extra separator, tracked extra case,
symlinked guest and dirty source). The nine-case committed selftest
and the genuine native compiler were **not** run locally. These tests
prove only the isolated source-only gate, not Oreslang runtime parity.

**Next action:** authorized protected-runner admission and actual 14 demo
+ 4 Java/Graal baseline guest execution, then independent code review;
keep this PR draft until the evidence is recorded.
