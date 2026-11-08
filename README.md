# atto-step-function-demo

Workflow and step-function examples demonstrating asynchronous orchestration in AttoLang.

## Project scope

Step execution, result projection, cancellation, and workflow state.

## Development and validation

Document the specific `.atto` source, expected results, supported backend/toolchain, and commands that have been executed.

## Status

This is a statement of intended scope, not a claim of completed implementation or production readiness. Source, CI, and checked-in examples are authoritative for actual supported features and commands.

## Ecosystem

- [AttoLang organization](https://github.com/atto-lang)
- [Language specification](https://github.com/atto-lang/atto-spec)
- [Platform conformance](https://github.com/atto-lang/atto-platform-conformance)

## Repository ownership and contribution routing

**Belongs here:** Step-function style workflow example, explicit state transitions, durable checkpoint contracts, retries and task cancellation.

**Belongs elsewhere:** Reusable state machines belong in atto-stategraph.atto; generic task composition in atto-rx-tasks; production deployment in atto-co.

**Security and portability boundary:** Require idempotency keys, bounded retries and timeouts, durable transition fencing, replay tests and resource reclamation after cancellation.

AttoLang is the public name; preserve existing Oreslang/.ores compatibility and use canonical .atto for new portable library source. This README defines scope, not feature readiness.

**Acceptance:** name exact source SHA/tree, runtime/toolchain, positive and negative checks and execution receipt before claiming support. Host-only tests and empty CI steps do not prove guest execution.
