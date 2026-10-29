# Native workflow implementation boundaries

The workflow code is exclusively Oreslang (`workflows/*.ores` and `examples/oreslang/*.ores`). JSON files are static graph-design artifacts; CI uses shell commands only to invoke the real Oreslang runtime and assert output.

This change intentionally retires the Node.js graph runner, host actor handlers, JavaScript memory ledger, JavaScript GitHub evidence checker, npm tasks, and Node tests. Their prior test evidence concerned JavaScript and must never be quoted as native Oreslang acceptance.

**Current native coverage:** eight proposed guest programs, all execution claims `NOT_EXECUTED` until run through the compiler from this exact tree. The upstream Java/Graal guest test in PR #2241 covers three separate basic actor examples, not this tree.

**Security:** fixture verification and fixture review are intentionally not authoritative. No production GitHub evidence ingestion, token use, deployment, durable memory, external side effects, exact-once execution or restart-safe actor migration exists yet. Input outside known fixture strings routes to rejection/quarantine; no claim of authenticated identity is made.

**Required next backend work:** implement versioned Workflow actor state, one-owner execution lease spanning suspension, actual actor-owned arenas/isolation, strict typed graph admission, bounded retries and cancellation, persistent inbox/outbox, storage-enforced activation fencing, crash recovery, and signed/authenticated evidence adapters where required.

Private-source cross-org CI mirror remains disallowed absent independent authorization. A step-less GitHub Actions failure is a runner-admission failure, not a compiler verdict.


## Audit restrictions (2026-10-29)

The eight source fixtures are fixed in-memory actor message paths, **not a
reusable typed graph executor, not a durable workflow engine and not proof of
isolated heaps**. Current compiled syntax in the Graal reference parser uses
`actor` and `isoactor`; the requested `define isolated actor` spelling is
a compatibility task that must be delivered through the compiler before the
fixtures switch to it. Default `actor` declarations should not be mistaken
for physically isolated worker heaps.

The order scenario sends payment/inventory fixture strings and performs no real
external effects. It does not implement compensating transactions or retry
failed payments. The separate bounded retry fixture demonstrates two declared
attempts, **not generic backoff**. The cancellation fixture exits before
downstream work, **not preemptive in-flight cancellation**. Fixture approval
and verified-evidence strings confer no security capabilities.

The JSON graphs under `graphs/` are conceptual targets, not an executable
runtime. Their semantics must not be cited as covered by the eight .ores
scenarios unless the actual guest run verifies them. The driver must record
real compiler identity and exact committed source blobs.
