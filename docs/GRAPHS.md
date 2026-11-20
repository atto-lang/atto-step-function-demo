# Graphs executed by native Oreslang programs

These diagrams describe the control flow implemented in `workflows/*.ores`; there is **no** JSON/JavaScript interpreter in the demo.

```mermaid
flowchart LR
  V[ValidateOrder actor] --> C{Accepted?}
  C -->|no| F[Reject]
  C -->|yes| I[ReserveInventory actor]
  C -->|yes| P[AuthorizePayment actor]
  I --> J{Both succeeded?}
  P --> J
  J -->|yes| S[Complete]
  J -->|no| X[Fail closed]
```

```mermaid
flowchart LR
  A[CaptureEvent actor] --> B[VerifyFixture actor]
  B --> C{Known local fixture?}
  C -->|yes| D[IndexEphemeral actor]
  C -->|no| E[Quarantine]
```

```mermaid
flowchart LR
  A[PrepareRelease actor] --> B{Approved fixture?}
  B -->|no| C[Waiting / rejected]
  B -->|yes| D[PreviewOnly actor]
```

The memory and approval fixtures demonstrate branching only, not real authentication, persistence, or an AWS-compatible durable execution protocol. The static `graphs/*.json` files are **not** executable definitions.
