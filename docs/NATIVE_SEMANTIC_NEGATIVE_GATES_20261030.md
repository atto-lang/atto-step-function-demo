# Native compiler state negative gate — 2026-10-30

The integration draft now adds two compiler-backed rejection challenges after positive checking and execution of all fourteen native workflow fixtures. The exact same pinned compiler must reject a read-only critical[read] state loan that still writes s.phase, and direct self.phase access instead of borrowed s.phase.

The checks reject exit success, timeout, launch failure, signal/crash, silence, and oversized diagnostics. The invalid sources are generated in private temporary storage and never counted as successful guest output cases.

The source-only selftest uses synthetic compiler stubs: one diagnostic rejection, six bad exit statuses, and one silent failure. It verifies shell guard behavior only, not an Oreslang compiler. Even genuine compiler rejection may be for the wrong reason unless the diagnostics are reviewed and the positive original guest is accepted.

Source-org CI at PR #11 head had failed Actions jobs with zero executed steps, NOT_EXECUTED. No private source tree was exported or copied to another organization. Independent code review, protected-main rules, trusted compiler provenance and actual exact-head native guest results remain required before merge.
