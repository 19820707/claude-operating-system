<!-- Engineering OS — ../../CLAUDE.md + ../../.agents/OPERATING_CONTRACT.md -->
<!-- Invariant: triage = route first; never fix before scope is established. -->
<!-- Never: declare SEV without evidence from logs, metrics, or user report. -->
<!-- Fail closed: unknown SEV -> assume SEV-2 until scoped. -->

# /incident-triage

Active incident response. Reproduces, scopes, and routes a live production or test failure.

## Loop (OPERATING_CONTRACT.md)

`REPRODUCE -> DIAGNOSE -> ISOLATE -> FIX -> TEST -> EVIDENCE -> DOCUMENT -> ROLLBACK`

## SEV classification

| SEV | Impact | Response |
|-----|--------|----------|
| SEV-1 | All users blocked / data loss / revenue stopped | Immediate; Opus mandatory |
| SEV-2 | Majority impacted / critical path degraded | < 30 min; Opus mandatory |
| SEV-3 | Minority impacted / workaround exists | < 2 h; Sonnet |
| SEV-4 | Cosmetic / monitoring alert | Scheduled; Sonnet |

## Triage output (before any fix)

```
SEV: 1 | 2 | 3 | 4
Surface (A-E): ...
Repro: ...
Blast radius: ...
Immediate mitigation: rollback cmd | feature flag | none
Root cause hypothesis: ...
Human approval required: yes | no
```
