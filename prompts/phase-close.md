# Prompt: phase-close

Execute at the end of every work phase to capture learning and update operational state.

---

## Sequence

### 1. Collect evidence
- Run `git status --short` — what changed?
- Run `git log --oneline -3` — what was committed?
- Run target tests — PASS or FAIL?
- Run `npm run typecheck` (or equivalent) — 0 errors?

### 2. Update `.claude/session-state.md`
Fill in:
- branch + HEAD commit
- objective of the phase just closed
- what was implemented (files + contracts)
- working tree pending (uncommitted changes)
- decisions taken (with justification)
- risks: resolved / new / still open
- checks executed + results
- rollback available
- next minimum steps
- what was explicitly left out of scope

### 3. Append to `.claude/learning-log.md`

```markdown
### Phase <name> — <date>
**Objective:** ...
**Result:** success / partial / blocked

**Learned:**
- [evidence observed → pattern identified]

**Failed:**
- [what did not work and why]

**Became a rule:** (H? reference if promoted)
- H? — [heuristic name]

**Avoid:**
- [confirmed anti-pattern]

**Next minimum step:**
- [concrete action]
```

### 4. Promote new heuristics (if any)
If a new pattern was confirmed in this phase:
- add H<n+1> to `heuristics/operational.md` (global) or project equivalent
- reference it in the learning-log entry

### 5. Confirm checks
```
git status        — working tree state
git log -3        — recent commits
[target tests]    — PASS/FAIL
typecheck         — 0 errors?
```

---

## Rules

- Distinguish always: evidence / inference / decision
- Do not call it a regression without evidence
- Do not close without rollback documented
- If phase partially failed → document exact cause, do not simplify
- If new heuristic confirmed → promote it now, not later
