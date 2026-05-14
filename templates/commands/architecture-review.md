<!-- Engineering OS — ../../CLAUDE.md + ../../.agents/OPERATING_CONTRACT.md -->
<!-- Invariant: architectural reading precedes any structural change; never redesign from chat memory. -->
<!-- Never: edit before top-10 risks are listed. -->
<!-- Fail closed: boundary unclear -> map it before proposing change. -->

# /architecture-review

Structural review of a module, domain, or change boundary. Produces risk map and phased plan.

## Sequence

1. Read CLAUDE.md + session-state.md + OPERATING_CONTRACT.md
2. Map current flow: entry points, data paths, trust boundaries, dependencies
3. Identify top 10 risks (correctness, security, reliability, observability, coupling)
4. Propose phased plan -- smallest blast radius first
5. Gate -- human approval required if plan touches critical surfaces (CLAUDE.md)

## Output format

```
### System reading
### Risk map (top 10)
### Proposed plan (phases)
### Classification (A-E) + Mode + Model
### Human approval required: yes | no
```
