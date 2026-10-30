# Native Step Functions integration: exact source-gate evidence (2026-10-29)

**Scope: LOCAL SOURCE-ONLY VERIFICATION. Not a Graal/LLVM native guest compilation, CI PASS, durable workflow, or security authorization.**

## Current integrated source checkpoint

- Step Functions PR #11 parent source head: `582f47b638626cade161bafac8215f213b4b29a2`, root tree `9e0e47b4f7277634306c36af1315b2875ac78017`
- Exact parent merge base: `893a0ce1b22990e0bde44b30933f85135441e42f`
- The merge reconciles fourteen `.ores` cases with `main`'s newer manifest-bijection/inventory and source-hygiene gates. The new bijection gate is shell/awk and rejects duplicate stdout oracles; it does not reintroduce Python or the previous nine-case assertion.
- Workflow actor and effect receipt actor use canonical `critical[write]` with a synchronous void callback and publish replies after closing their state loans.

## Local POSIX shell, Bash and jq tests

These scripts were reconstructed inside a **temporary synthetic local Git repository**. Every script hash below was verified against its GitHub Git blob identity before execution. The `.ores` workflow files in that local reproduction were synthetic placeholders, not downloaded native guest programs.

| Committed file | Exact Git blob | Local source-only result |
| --- | --- | --- |
| `ci/check-native-manifest.sh` | `46ba56c2e46c65f8ac70fcadd4165e2df1997b16` | Positive 14/14 manifest inventory PASS against synthetic tracked files |
| `ci/test-native-manifest.sh` | `652c7ce9990418a00dca5969b65f0c799e3c0847` | Eight rejection cases PASS (including missing compiler, missing/duplicate/unsafe cases, symlinks, unlisted and dirty guest files) |
| `ci/verify-build-info.sh` | `7777a19272ea0981affa3bdaa5ce1d21e7ffb3b1` | JSON validator exercised by its exact negative suite |
| `ci/test-build-info.sh` | `0a79a4f51d94af2b8113fc08e96bdd800a7ead50` | Two valid cases admitted; seventeen malformed/false/ambiguous JSON cases rejected |
| `ci/source-policy.sh` | `1b644de07153b7eb2dfba44bbe00161833817f8c` | Strict source-policy script exercised by its exact negative suite |
| `ci/test-python-source-policy.sh` | `00aa4a71a4098301672dd01b715f104546e1c04f` | Eight source-policy adversarial cases PASS |

Local derived shell/awk check on the current fourteen-case `ci/native-cases.txt` (blob `eff4226514cd2dbda9536c3804e8c7598550312e`) admitted the original manifest and rejected a duplicate stdout oracle. This derived check is not a claim of executing the hosted workflow verbatim.

**Important qualification:** The local `ci/test-native-manifest.sh` missing-compiler challenge used a synthetic intentionally failing `ci/verify-native.sh` stub. The complete real compiler verification script and the integrated repository-wide source audit were **not** locally executed. No actual native Oreslang compiler, JVM/Truffle guest, AOT artifact, persistent actor, or external receipt was exercised.

## Same-org Java/Graal guest resource identity

For this exact source tree, all **14/14** `workflows/*.ores` Git blobs match the corresponding `src/test/resources/parity/step-demo-v1/*.ores` blobs on Java/Graal PR #2246 at `4c85419eb612a963a6bad8086a7ce95960707ffb`. The sealed coordinator blob is `5c79f0f49593f501a525369c0f1b47b38ada8790`; the isolated effect ledger blob is `58e9bda1709c015bb7fa17693c8f08ad384a397c`. This is **source parity**, not compilation or a valid runtime verdict.

## GitHub Actions and promotion blockers

- Exact-head source-org runs: manifest bijection `41004320496`, source hygiene `41004320466`, inventory `41004320469`, and native workflows `41004320502`: all completed failure without recorded job steps (`steps=null`). Rerunning `41004320496` also ended with `steps=null`. Classify these as **NOT_EXECUTED**.
- `main` currently reports `protected=false`, required-status-check enforcement `off`, and no independently recorded approval on PR #11.
- Before merging: obtain actual executable 14 demo + 4 Java baseline guest results, trusted compiler build provenance and SHA-256, negative parser/loan cases, integrated source-shell gates with nonzero runner steps, independent approval, and effective branch protection. Do not export private source across organizations without separately approved source/destination authorization.

All local tests occurred without cross-org private-source transfer, credentials, or a fake native guest PASS.
