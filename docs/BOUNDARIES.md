# Native workflow implementation boundaries

The workflow code is exclusively Oreslang (`workflows/*.ores` and `examples/oreslang/*.ores`). JSON files are static graph-design artifacts; CI uses shell commands only to invoke the real Oreslang runtime and assert output.

This change intentionally retires the Node.js graph runner, host actor handlers, JavaScript memory ledger, JavaScript GitHub evidence checker, npm tasks, and Node tests. Their prior test evidence concerned JavaScript and must never be quoted as native Oreslang acceptance.

**Current native coverage:** six proposed guest programs, all execution claims `NOT_EXECUTED` until run through the compiler from this exact tree. The upstream Java/Graal guest test in PR #2241 covers three separate basic actor examples, not this tree.

**Security:** fixture verification and fixture review are intentionally not authoritative. No production GitHub evidence ingestion, token use, deployment, durable memory, external side effects, exact-once execution or restart-safe actor migration exists yet. Input outside known fixture strings routes to rejection/quarantine; no claim of authenticated identity is made.

**Required next backend work:** implement versioned Workflow actor state, one-owner execution lease spanning suspension, actual actor-owned arenas/isolation, strict typed graph admission, bounded retries and cancellation, persistent inbox/outbox, storage-enforced activation fencing, crash recovery, and signed/authenticated evidence adapters where required.

Private-source cross-org CI mirror remains disallowed absent independent authorization. A step-less GitHub Actions failure is a runner-admission failure, not a compiler verdict.
