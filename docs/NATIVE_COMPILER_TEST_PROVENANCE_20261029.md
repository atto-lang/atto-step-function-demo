# Native compiler acceptance evidence — 2026-10-29

Nine exact Git blob SHA-1 objects from this demo branch were copied **within
the same private organization**, not across organizations, into compiler
PR [#2241](https://github.com/ores-truffle-oreslang/oreslang-source.java/pull/2241).

Compiler test SHA: `6123cbe890ae79a7eca12ddcdaa490f724f31930`.
Source fixture SHA: `0ba32f019a0c1dfcf9aaa2f91accb030178f5a45`.
The compiler JUnit test first calculates each native fixture's canonical
Git blob identity and then calls the Graal guest Context with that same source.
The test asserts exact stdout for each case. It fails closed on a parsing,
runtime, blob identity or expected-output mismatch.

The targeted Actions workflow is limited to this private compiler repository,
uses read-only permissions, and runs `mvn -B -ntp
-Dtest=SourceActorStepWorkflowExecutionTest,SourceActorDemoWorkflowExecutionTest
test` with a real GraalVM/Java setup. If the source organization keeps
returning zero-step failures, no test result has been established.

This is **not** compiler-backed proof until GitHub records actual executed
steps, JUnit XML reports and expected PASS markers. Successful execution
would establish in-memory guest fixture behavior only; persistence,
fenced critical actor state, authenticated approvals and full AWS Step
Functions semantics require separate acceptance.

Native fixture map, SHA anchors and known limitations remain in
`GRAPH_CONFORMANCE.md`. No private source was transferred to a
cross-organization carrier while issue #22 remained open.

### Saga extension

Three further `.ores` saga fixtures were authored in compiler PR #2241 and
copied byte-for-byte back into the same-organization private demo PR #7:
- `order-saga-success.ores`: `1d47ce2cfb929d43a7501fbc4bf2363ec2195fde`, expected `saga:complete`
- `order-saga-compensated.ores`: `d4782060ff0f53588b00e8c2eb9b7f87f5824e3d`, expected `saga:compensated`
- `order-saga-ambiguous.ores`: `51ca94e1cbf983a495ed89f1531e9e740d50c34d`, expected `saga:reconciliation-required`

**Current targeted suite: 12 demo guests + 3 baseline guests = 15 source
execution cases.** All compiler run evidence remains NOT_EXECUTED unless
nonzero steps and passing JUnit reports are subsequently verified.


## Exact current 12-source reconciliation

At demo head `a6ad05781b021c10d93ee4d812d2189040229931`, all **12**
`workflows/*.ores` Git blobs matched the 12 resources in Java/Graal
PR #2241 (compiler branch head `125a950dc06fc74f36ea7874270f91c8992b0063`)
byte-for-byte. The compiler guest workflow checks 12 demo JUnit tests plus
three baseline source-actor JUnit tests. This is **15 proposed guest test
cases**, not 15 executed successes. The demo-source CI runs
`40825791216` and `40825785091` again failed with zero recorded steps;
no compiler/runtime verdict is available.

The parser's `--build-info` option is implemented by the Java CLI, but an
arbitrary `ORESLANG_BIN` or self-reported JSON alone cannot certify runtime
provenance. The verifier additionally demands an expected binary SHA-256,
negative syntax rejection, and exact Git-blob source identity. A trusted
compiler build identity still requires independent verification.

## Current 13-case integration reconciliation (source-only)

The source integration branch includes an additional `order-saga-void-unknown.ores` guest and a revised sealed-state coordinator. Prior 12-case Git blob matches and proposed JUnit cases are historical evidence, **not proof that this exact 13-guest tree was compiled or executed**. The 13th case and the compiler spelling `critical-write` must be checked on the exact Java/Graal guest compiler head. Pending job-admission and independent review remain release blockers.
