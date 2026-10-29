# Native Oreslang checkout saga: source-guest fixtures

Three independent `.ores` programs exercise actor messages, observed replies, and explicit bounded routing without JavaScript:

| Source | Expected stdout | Meaning |
| --- | --- | --- |
| `workflows/order-saga-success.ores` | `saga:complete` | Three acknowledged successful steps, no compensation |
| `workflows/order-saga-compensated.ores` | `saga:compensated` | Fixture's shipment rejection is explicitly known to have performed no effect; execute `VoidSagaPayment`, then `ReleaseSagaInventory` |
| `workflows/order-saga-ambiguous.ores` | `saga:reconciliation-required` | A synthetic unknown shipment reply cannot authorize automatic compensation |

Run `ORESLANG_BIN=/absolute/path/to/actual/oreslang-compiler sh ci/verify-native.sh` to check and execute all eleven native scenarios. No shim, JS simulator, Maven-only host source test, or fake stdout substitutes for running actual Oreslang guest code. Provide `ORESLANG_COMPILER_SHA256` to pin compiler bytes; the harness always logs their SHA-256.

## Safety and failure boundaries

- These are fixture-only strings, NOT payment/inventory/shipping adapters. A real step must provide an independently trustworthy, authenticated receipt before its result may be classified as `rejected-no-effect`.
- The compensation example explicitly executes payment undo **before** inventory undo. A compensation failure returns `saga:compensation-incomplete` if a reply is not acknowledged as expected. The source examples do not implement retries of compensation.
- An exception, timeout or crash during a real external operation can be ambiguous. The third fixture simulates this **as an actor reply**; it does not implement or test real timeout delivery or physical actor cancellation.
- No exactly-once external side effects, persisted step state, provenance of receipts, tenant authorization, durable inbox/outbox, storage fencing, recovery or secure human approvals are implemented.
- The `main` routine performs in-memory orchestration. Native **isolated workflow coordinator with sealed state** and production-safe activity protocols remain upstream work, detailed in `WORKFLOW_COORDINATOR_V0.md`.
- The graph JSON is design/documentation metadata only; a native actor graph implementation must not silently replace `.ores` execution with a host-language graph interpreter.

## Next acceptance matrix

1. Compile and run all 11 native sources with an exact pinned Java/Graal compiler, capture actual runner jobs and step logs, compiler SHA-256, demo Git SHA and stdout.
2. Run guest tests for duplicate delivery, wrong step receipts, actor cleanup, cancellation, and divergent compensation acknowledgments; do not equate these source fixtures with that coverage.
3. Implement actor-owned state and a storage-fenced transaction boundary before adding real external effects.
4. Repeat the exact fixtures and fault conditions on LLVM, .NET NativeAOT, Wasm, and other relevant Oreslang backends independently.
