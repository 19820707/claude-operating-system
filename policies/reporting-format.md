# Reporting Format Policy

Standard structure for analysis, proposals, and execution results.
Consistent format reduces cognitive load and makes outputs auditable.

---

## Diagnosis response

Use when analysing a problem, reading a codebase, or assessing risk.

```
## Evidence
- [observed fact — file:line, output, git log]

## Conclusion
- [what it means — inferred from evidence]

## Next step
- [one concrete action]
```

Always distinguish:
- **Evidence** — observed (file, output, test result, git log)
- **Inference** — derived (pattern, root cause hypothesis)
- **Decision** — chosen (action, recommendation)

Never present inference as evidence. Never present decision as fact.

---

## Pre-implementation plan (7 points)

Required before any non-trivial edit:

1. Exact current flow
2. Exact change point
3. Exact files to create/alter
4. Expected functional/technical contract
5. Minimum tests/checks
6. Regression risk
7. Rollback
8. Why this is the smallest correct change *(optional but recommended)*

---

## Execution result (standard close)

Required after any implementation:

| Field | Content |
|-------|---------|
| Files changed | List with operation (M/A/D) |
| Diff summary | Key changes, not full file |
| Checks executed | Command + result |
| Result | PASS / FAIL / PARTIAL |
| Residual risk | What could still go wrong |
| Rollback | Exact command |

---

## System review response

Use for architecture reads, risk assessments, roadmap proposals.

```
### 1. System Reading
- what was found
- how the system appears to be structured
- assumptions / uncertainties

### 2. Risk Assessment
- critical / high / medium risks
- unknowns

### 3. Execution Plan
- current phase / target files / intended change
- expected impact / validation strategy / rollback

### 4. Execution Result
- files changed / checks / outcomes / residual risk / rollback
```

---

## Gap analysis table

| Gap | Impact | Risk of not resolving | Value | Reversible |
|-----|--------|-----------------------|-------|------------|

---

## Roadmap table

| Phase | Objective | Value | Risk | Effort | Dependencies |
|-------|-----------|-------|------|--------|-------------|

---

## Rules

- Never start with "I'll..." or "Let me..." — lead with the action
- Never end with a summary of what you just did — the diff is visible
- Never use motivational language or filler transitions
- If uncertain → say explicitly "evidence insufficient to conclude X"
- If out of scope → say "registering as out of scope, not resolving now"
