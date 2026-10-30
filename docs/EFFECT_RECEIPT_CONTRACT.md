# Native effect-receipt ledger: acceptance contract

**Status: source-guest candidate. Real Oreslang compiler execution NOT_VERIFIED.**

## One actor, one state schema

The `WorkflowEffectLedger` is declared `define isolated actor` and owns all guest instance data inside one `state { phase: String, transition_epoch: int }`. The single-flight receive turn performs check/update inside one `self.handle_state(critical[write] |s| -> { ... })` callback. The callback returns void and writes only a detached local scalar response; `self.send` and `self.end` are outside the critical loan.

## Expected synthetic transitions

| Input | Previous phase | Output | Next phase |
| --- | --- | --- | --- |
| `tenant-b:run-1:prepare` | created | rejected | created |
| `tenant-a:run-1:prepare` | created | prepared | prepared (epoch 1) |
| duplicate prepare | prepared | rejected | prepared |
| `tenant-a:run-1:dispatch` | prepared | unknown | dispatched-unknown (epoch 2) |
| cancellation while unknown | dispatched-unknown | blocked-unknown | unchanged |
| foreign synthetic reconciliation | dispatched-unknown | rejected | unchanged |
| synthetic not-applied reconciliation | dispatched-unknown | known-not-applied | known-not-applied (epoch 3) |
| duplicate reconciliation | known-not-applied | rejected | unchanged |
| retire | known-not-applied | retired | retired (epoch 4) |

Expected exact stdout for the complete fixture: `effect:fixture-reconciled-no-replay`. The actor has no storage, no real network calls, no durable messages or authenticated receipt channel. Its fixed message strings are NOT proof of a provider-signed receipt or tenant authorization. An actual timeout is not tested.

## Production admission requirements

1. Compile and execute this exact `.ores` blob with a verified Java/GraalVM compiler, exact demo SHA and nonzero runner steps. Verify failure behavior against the compiler's negative state-loan fixtures. The canonical bracketed `critical[write]` syntax is not assumed compiler-verified.
2. Persist prepared command and deterministic idempotency key before dispatch; atomically commit consumed inbox + state + events + outbox intents + timers with storage-enforced activation fencing.
3. Obtain an independently verified, tenant-bound external receipt (or explicit reconciliation) before resolving an UNKNOWN dispatch. The model must not trust the LLM, untrusted actor message or caller string as an authority.
4. Stop retries and compensation on unknown outcome, protect epoch/run/incarnation identity, supervise cancellation and drain child operations. An external effect ACK is not a durable commit.
5. Test crash windows around persisted intent, dispatch, receipt and checkpoint, including duplicates, delayed receipts, stale epochs, forgery and process restart.
6. Independently execute LLVM/.NET/Wasm backend parity and show physical actor-owned arena/heap isolation; do not claim exactly-once effects or hard real time until bounded dispatch and admission are proven.

The Step Functions source and its CI checker are intentionally pure Oreslang plus shell harness, with no Node/Python workflow engine. The AI-agent demo's `WorkflowEffectLedgerActor` serves as an architectural comparator, not a copied or automatically imported runtime.
