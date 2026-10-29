# Workflow coverage and graph drift matrix

The `graphs/*.json` files remain **design-only targets**, not parsed workflow definitions. No JSON graph is executed by a host runtime. These files are not authoritative for the native actors; the Oreslang program behavior is the only executable contract.

| Design intent | Native .ores source | Covered in source | Still missing |
| --- | --- | --- | --- |
| Order accept + parallel join | `order-workflow.ores` | Two spawned actors and explicit join on fixture replies | Real inventory/payment effects, retry, compensation, deadline |
| Order reject | `order-rejected.ores` | Reject before downstream actors spawn | Structured input validation, explicit admission budget |
| Memory path | `agent-memory-workflow.ores` | Capture → fixed verification fixture → ephemeral index | Authenticated CI evidence, persistence, tenant authorization |
| Memory quarantine | `agent-memory-quarantine.ores` | Reject untrusted fixture | Genuine verifier integration and durable quarantine |
| Release review | `release-review-workflow.ores` | Fixed approval fixture → preview-only actor | Authentic human approval, durable waiting, no auto-approval in production |
| Release waiting | `release-waiting.ores` | Stop at pending fixture state | Persisted wait state and authenticated wake-up signal |
| Bounded retry | `bounded-retry.ores` | Maximum two explicit attempt actors | Error classification, budget, backoff, idempotent effects |
| Cancellation | `cancel-before-work.ores` | Stop before spawning work | In-flight cancellation, cleanup receipts |
| Actor-owned workflow state | `coordinator-state.ores` | Phase FSM, foreign fixed-run string rejection, out-of-order and duplicate-start guards | Trusted tenant IDs, durable fencing, real graph traversal |

## Divergence that must not be ignored

- `graphs/order-pipeline.json` advertises per-node `maxAttempts`, but the normal order actor fixture does **not** retry. The bounded-retry program is separate.
- `graphs/release-review-pipeline.json` advertises a `wait` node; the positive source fixture uses a hardcoded review signal immediately. The negative waiting case is a separate source program; neither persists an approval wait.
- `graphs/agent-memory-pipeline.json` names a real evidence verifier and storage; the native fixture uses a fixed string and no storage.

**Conformance rule:** Until a native Oreslang graph parser, typed actor-edge admission and a durable workflow actor are implemented, do not call the JSON files *runnable*, do not infer executable semantics from them, and do not use a simulator's test success as guest proof. Every new source workflow must be added to `ci/native-cases.txt` with explicit expected stdout and executed with a pinned compiler.

## Actor state mutation coverage

`coordinator-state.ores` is a non-durable **legacy compatibility**
fixture. It uses the ordinary `compatibility_phase` field and
`route_event()` method to check a basic in-memory phase FSM. It must **not**
be described as canonical actor state. Compiler support for `state { ... }`
and an unforgeable sealed `self.handle_state(...)` critical loan is pending
(upstream Java/Graal issues #633 and #1349); suspension safety, guarded state
access and store-enforced fencing remain NOT_IMPLEMENTED.

## Saga fixtures — not durable compensation

| Fixture | Executable in-memory behavior | Not implemented |
| --- | --- | --- |
| `order-saga-success.ores` | No external effects; all forward steps succeed | Real effects, authenticated receipts, durable rollback and crash recovery |
| `order-saga-compensated.ores` | Known no-effect rejection; reverse-order compensators | Real effects, authenticated receipts, durable rollback and crash recovery |
| `order-saga-ambiguous.ores` | Unknown outcome quarantined; no blind compensation | Real effects, authenticated receipts, durable rollback and crash recovery |
