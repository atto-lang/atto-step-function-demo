# Native Oreslang CI admission hardening — 2026-10-29

**Classification: source-only security self-tests, NOT Oreslang guest execution.**

This draft branch extends the native checkout saga to **twelve** `.ores`
fixtures, while preserving the existing shell-only compiler runner and the
ban on JavaScript/Python implementation code.

## Exact source-only evidence

- `ci/check-native-manifest.sh` Git blob: `ea59025a3dbc9f36cc6e44ea081d70baeae25070`
- `ci/test-native-manifest.sh` Git blob: `652c7ce9990418a00dca5969b65f0c799e3c0847`
- Those scripts were reconstructed byte-for-byte in a local private synthetic
  Git repository, then compared with `git hash-object`: **both matched** the
  corresponding GitHub blobs.
- `sh -n` passed; a valid tracked twelve-file manifest was admitted.
- The isolated source-free test command `sh ci/test-native-manifest.sh`
  passed **eight of eight negative tests**, rejecting:
  missing compiler, missing fixture, duplicate fixture, traversal path,
  output contract injection, symlinked guest, unlisted source, and dirty source.
- The real `ci/verify-native.sh` additionally checks canonical one-segment
  source path names, rejects symlinks/irregular Git file modes, binds exact
  expected checkout SHA, requires a pinned executable SHA-256 and
  `--build-info`, and compares actual compiler guest stdout byte-for-byte.
  These are source-code protections, not proof it actually ran.

## Exact Oreslang guest acceptance still pending

The authoritative twelve-case guest manifest is `ci/native-cases.txt`.
Every source must be parsed, typechecked and **executed** by a genuine
Oreslang compiler with matching bytes and bounded stdout; in-memory actor
behaviour alone is not production Step Functions durability.

Within the **same private GitHub organization**, the three new saga `.ores`
fixtures were copied into
[Java/Graal PR #2241](https://github.com/ores-truffle-oreslang/oreslang-source.java/pull/2241)
with independently matching Git blobs:

| Fixture | Exact source Git blob |
| --- | --- |
| `order-saga-success.ores` | `1d47ce2cfb929d43a7501fbc4bf2363ec2195fde` |
| `order-saga-compensated.ores` | `d4782060ff0f53588b00e8c2eb9b7f87f5824e3d` |
| `order-saga-ambiguous.ores` | `51ca94e1cbf983a495ed89f1531e9e740d50c34d` |

Java PR #2241 now declares **15 guest JUnit tests** (three actor-step
baselines plus twelve demo fixtures). These tests use real
`Context.eval` when executed, but **have not run successfully** on
the current source-org runner. A zero-step GitHub Actions failure is
`NOT_EXECUTED`, not a passing source test.

## Merge and confidentiality gates

- **No private-source cross-organization mirroring** while
  [P0 incident #22](https://github.com/ores-truffle-oreslang/oreslang-platform-conformance/issues/22)
  remains open. An alternate private repo with available Actions minutes
  does not itself authorize copying proprietary source.
- No compiler native executable with trusted digest was available in the
  local audit environment; `ci/verify-native.sh` real guest execution is
  **NOT_EXECUTED**.
- The coordinator state-loan PRs #9 and #10 require reconciliation with
  the current Java compiler forward-port (#2245). Neither should merge
  before compiler-backed positive/negative guest tests.
- Durable inbox/outbox, storage fencing, authenticated CI and human
  approvals, restart recovery, and five-backend guest parity are **not
  implemented or certified** by this source-only audit.

## 13-case extension after the original selftest

The eight source-free negative tests above were executed against an **earlier twelve-case snapshot**, not the current thirteen-fixture branch. The new `order-saga-void-unknown.ores` has been added to the manifest and `ci/check-native-manifest.sh` now enforces exactly **13** cases. That updated check and the full 13-case guest outputs remain **NOT_EXECUTED** on the latest branch head; never reinterpret the historical 8/8 shell tests or 12-case Java JUnit fixture inventory as a current-head passing run. Java PR #2241 also needs the new negative compensation fixture and real native execution before 13-case equivalence can be claimed.
