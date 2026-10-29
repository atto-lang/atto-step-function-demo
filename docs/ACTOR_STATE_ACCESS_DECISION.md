# Workflow coordinator state-ownership decision (source proposal)

**Status: proposed source contract; no native compiler execution proof.**

PR #10 is the selected main-targeted candidate. PR #9 is stacked on saga #6 and overlaps its implementation. Both remain draft until actual Java/Graal guest compilation, compiler-negative checks, and protected-branch review. Do not merge both.

## Canonical candidate

- At most one `state { ... }` schema; no persistent ordinary instance fields, direct `self.phase` or `self.state`, compiler-internal state handle overrides, or illicit aliases.
- Use `self.handle_state(critical-write |s| -> { ... })` for an exclusive loan, as specified in [Java workflow issue #2236](https://github.com/ores-truffle-oreslang/oreslang-source.java/issues/2236). `critical write` and bare `critical` in earlier PR drafts are not silently accepted alternate spellings. Parser/type checker acceptance is still unverified.
- Declare `with state.read, state.write` as upper-bound effects on the handler; they do not themselves grant a state capability.
- Perform one synchronous read/check/update under the loan and return a detached owned scalar. No `await`, `select`, `spawn`, `self.send`, `self.end`, FFI, or loan escape within the loan; publish messages and retire actors afterward.
- Fixed tenant/run strings are mock labels only, not authenticated identity or durable execution.

## Required executable proof

1. Build the exact Java/Graal compiler and execute the coordinator `.ores` guest with expected output and exact demo/compiler SHA and runner-backed logs.
2. Add compiler-negative guests for direct fields, direct state access, duplicate state, write under read-only loan, loan escape, suspended loan, conflicting write loans and user overriding `handle_state`.
3. Confirm old spelling rejection (unless the grammar explicitly accepts a reviewed alias); retain script-based mutation tests as *static checks only*.
4. Exercise the 13 saga/coordination guests on pinned Java/Graal, then independently on LLVM/.NET/Wasm/Forge. Source presence and source-free Actions canaries are not execution evidence.
5. Require real protected-main independent review, source-org runner admission, and exact-SHA evidence. Do not export private source across organizations without the independent incident disposition.

Tracking: [Java actor-state #1349](https://github.com/ores-truffle-oreslang/oreslang-source.java/issues/1349), [Java critical scopes #633](https://github.com/ores-truffle-oreslang/oreslang-source.java/issues/633), [GitHub governance #5](https://github.com/ores-truffle-oreslang/oreslang-step-function-demo/issues/5).
