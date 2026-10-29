# Oreslang Step Function Demo

**Production-language boundary: the implementation is Oreslang, not Node.js.**

This repo's `src/*.ores` contains actor-based workflows and graph transition rules.
The JS code formerly under `src/*.mjs` was an erroneous host-language
implementation. It has been moved **out of production source** to
`tests/reference/*.mjs` and is retained solely as a test oracle. Its tests
must never be cited as proof of Oreslang execution.

## Oreslang implementation

| Oreslang source | Actor graph | Current behavior |
| --- | --- | --- |
| [src/order_workflow.ores](src/order_workflow.ores) | ValidateOrderStep → WorkflowRouter → (InventoryStep + PaymentStep) → JoinStep | Actor messages, branch choice, parallel fork, explicit join |
| [src/memory_pipeline.ores](src/memory_pipeline.ores) | CaptureEventStep → VerifyEvidenceStep → QuarantineStep | **Fails closed** without independently authenticated CI evidence and native persistence |
| [src/review_workflow.ores](src/review_workflow.ores) | PrepareReleaseStep → ReviewGateStep | **Waits**, never deploys from a caller string |
| [src/saga_workflow.ores](src/saga_workflow.ores) | ReserveInventorySagaStep → AuthorizePaymentSagaStep → ShipOrderSagaStep → reverse compensation | Actor saga, known rejection compensation; ambiguous external effects require reconciliation |
| [src/step_graph.ores](src/step_graph.ores) | Pure typed string-state graph rules | Oreslang graph transition functions, no JS imports |

Each workflow source is independent and has its own `pub async routine main`.
The graph JSON files are source-free *reference test vectors*, not the
authoritative implementation. See [workflow diagrams](docs/GRAPHS.md).

## Testing

```sh
npm test                  # JS tests, including Oreslang source-boundary checks
npm run test:ores-source  # structural source tests only: NOT compilation
npm run test:reference    # host-language reference model regressions
npm run demo:reference    # reference simulation, NOT Oreslang execution
npm run demo:saga:reference # test-only saga simulation
```

**Important:** The Oreslang parser/compiler/Graal source guest has not been
successfully executed on this PR. Source-boundary checks only inspect text
and file placement. Do not represent Node reference tests as Oreslang runtime
support. These Oreslang sources follow the draft [Java source actor baseline
PR #2241](https://github.com/ores-truffle-oreslang/oreslang-source.java/pull/2241).

Durable inbox/outbox, storage epoch fencing, supervised parent workflow actors,
authenticated GitHub verification and real memory indexing require additional
native Oreslang capabilities; the memory and review examples deliberately refuse
unauthenticated advancement instead of claiming those capabilities exist.

## CI and security

GitHub-hosted Actions on the source org have previously failed before any
steps execute. No cross-organization export of private Oreslang source is
authorized while [security incident #22](https://github.com/ores-truffle-oreslang/oreslang-platform-conformance/issues/22)
remains unresolved. Keep this PR unmerged until real Oreslang guest compilation,
negative fixtures and provenance are recorded.

The old local Node acceptance reports remain historical test-only evidence.
They are not evidence of production Oreslang behavior.
