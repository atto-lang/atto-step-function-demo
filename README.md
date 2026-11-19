> **AI agent instructions (organization-wide):** Before working on code, issues, or pull requests, read and follow the [organization `AGENTS.md`](https://github.com/atto-lang/.github/blob/main/AGENTS.md), including its **merge-first stealth-development policy**. Honor any repository-local `AGENTS.md`, explicit holds, and GitHub-enforced rules.

# atto-step-function-demo

Workflow and step-function examples demonstrating asynchronous orchestration in AttoLang.

## Naming migration and language authority

This repository is maintained at [atto-lang/atto-step-function-demo](https://github.com/atto-lang/atto-step-function-demo); use `https://github.com/atto-lang/atto-step-function-demo.git` for Git remotes and canonical `.atto` source examples. The normative language contract is [atto-spec](https://github.com/atto-lang/atto-spec), with executable guest evidence tracked by [atto-platform-conformance](https://github.com/atto-lang/atto-platform-conformance). Follow current ownership, borrowing, effects, actor, and syntax rules there; do not infer implemented features from a README or unexecuted CI.

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

AttoLang is the canonical project name; new source, examples and documentation use `.atto` and the `atto-lang` repository organization. This README defines scope, not feature readiness.

**Acceptance:** name exact source SHA/tree, runtime/toolchain, positive and negative checks and execution receipt before claiming support. Host-only tests and empty CI steps do not prove guest execution.
