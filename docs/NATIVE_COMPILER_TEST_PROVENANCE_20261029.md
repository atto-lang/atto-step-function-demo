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
