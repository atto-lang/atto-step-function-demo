# Cross-demo review: native Step Functions versus AI-agent coordination

**Source-only integration audit, 2026-10-29.** Comparing private repos within the original organization; no code copied across organizations, no native guest execution claimed.

| Dimension | Step Functions candidate | AI-agent actor graph | Remaining gap |
| --- | --- | --- | --- |
| Actor state | WorkflowCoordinator uses one sealed state phase and a critical-write handle_state proposal | 20 isolated actors with typed state schema and read/write loans | Both syntax and loan exclusion require exact-revision compiler acceptance, and physical actor-owned arena evidence |
| Workflow graph | main() drives fixed guest examples; three JSON diagrams are docs only | ExecutionGraphActor models bounded DAG nodes, dependency readiness, start/settle/cancel with revision guards | Native Task/Choice/Parallel/Wait/Retry/Catch/Map graph composer not implemented |
| Parallelism | Fixed child-actor fork/join | Bounded dependency scheduling | Need general bounded fanout/fanin, exactly-one branch winner and verified cancellation drain |
| External effects | Four saga fixture cases: success, known rejection, unknown shipment, unknown void | WorkflowEffectLedgerActor models prepared/dispatched/confirmed/unknown with epoch checks | Neither has transactional inbox/outbox, independently authenticated receipts or safe crash recovery |
| Memory | Fixed capture, verify, index/quarantine | Nine-actor memory pipeline and pinned invalidation | Durable checkpoint and memory recall contract not implemented in Step Functions |
| CI | 13 guest manifest; compiler digest and exact SHA pin; negative static probes | Source tests and draft native receipt validators | GitHub Actions zero-step failures, no compiler guest verdict and no backend parity |

## Required contracts

1. Each stateful actor has exactly one actor-owned state schema. No ordinary persistent instance fields, direct self.state, or escaped borrowed references. Stateless step actors need not fabricate persistent data.
2. Mutations happen under an exclusive sealed handle_state state loan; read-only work uses a read loan. No await, send, spawn, blocking I/O or external effect while the loan remains live. Actor turns stay single-flight.
3. A timeout means UNKNOWN until an authenticated receipt establishes applied/not applied. A compensation cannot be automatically issued against an unknown effect. Compensation failures also require reconciliation.
4. Preserve source-mode and source-blob checks, compiler SHA-256 and exact source identity, nonzero executed Actions steps, byte-exact native stdout, 13/13 source manifest, and deliberate invalid-grammar challenges.
5. Do not claim durability without atomic inbox consumed + state + events + outbox intents + timer update, monotonically fenced actor activation, versioned snapshot, idempotency and crash fault-injection tests.

## Merge reconciliation

- PR #6 provides the 13-case native checkout saga including void-unknown.
- PR #7 provides hardened source-policy, compiler provenance and CI negative tests.
- PR #10 provides the sealed coordinator state proposal. Its critical-write hyphenated spelling is described in Java issue #2236 but is not compiler-executed evidence.
- AI-agent PR #1 -> #2 -> #3 is a dependent stack; #5 (native evidence), #6 (state loans), and #8 (array escape) are overlapping hardening dependents and need base reconciliation.
- All branches are drafts and have no independently reviewed, exact-source, runner-executed native guest pass. Do not merge blindly into unprotected main or export private source across organization boundaries.

**Verdict:** source-only integration candidate, not native runtime or release-ready proof.
