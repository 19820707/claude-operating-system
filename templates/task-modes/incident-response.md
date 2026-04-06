---
name: incident-response
description: Structured workflow for active incidents — stabilize first, scope impact, form hypothesis, mitigate, document
type: task-mode
---

# Task Mode: incident-response

**Model:** Opus — always
**Mode:** Critical → Production if any mitigation touches live systems
**Approval:** Required before any production-touching action. No exceptions.

---

## When to use

- Active production failure (service down, feature broken, data anomaly)
- Elevated error rate detected by monitoring
- User-reported breakage in production
- Security event in progress
- Performance degradation affecting users

Not for: pre-production bugs, failing tests with no production impact, known issues not yet manifesting.

---

## Priority order (strict)

1. **Stabilise** — stop the bleeding. Rollback, feature flag, kill switch.
2. **Scope** — how bad is it, who is affected.
3. **Evidence** — gather facts before forming hypothesis.
4. **Hypothesise** — one hypothesis at a time, with supporting evidence.
5. **Mitigate** — smallest action that restores service.
6. **Confirm** — validate that mitigation worked.
7. **Document** — timeline, root cause, action taken.

Do not skip to step 4 before completing steps 1–3.

---

## Sequence

### 1. Stabilise first

Before investigating, ask:
- Is there an immediate mitigation available?
  - Feature flag to disable the broken feature?
  - Rollback to previous deployment?
  - Kill switch or circuit breaker?
  - Rate limit or block the triggering input?
- If yes and action is safe and reversible → apply first, investigate after.
- If no safe mitigation is available → proceed to scope.

**Never apply a mitigation that could make things worse without explicit human approval.**

### 2. Scope the impact

Answer these before anything else:
- What is broken? (service / feature / endpoint / user segment)
- What still works? (isolate the failure boundary)
- How many users affected? (all / subset / specific condition)
- Since when? (first error timestamp — check logs, not assumptions)
- Is the impact worsening, stable, or recovering?
- Is there data loss or corruption risk?

### 3. Gather evidence

```bash
# Recent commits (last 24h)
git log --oneline --since="24 hours ago"

# Recent deployments
# Check CI/CD deploy log or deployment history

# Error log extraction — per service:
# timestamp | error message | file:line | frequency | user segment

# Config or secret changes (check .env history, secrets manager audit log)

# Dependency version changes (package-lock.json diff vs last known good)
```

Do not form a hypothesis until evidence is gathered. "It was probably the last deploy" is not evidence — it is a guess.

### 4. Root cause hypothesis

Structure the hypothesis:
- **Hypothesis**: one sentence stating what is failing and why
- **Evidence supporting**: specific log lines, error messages, commit hashes
- **Evidence against**: what this hypothesis does not explain
- **Confidence**: high / medium / low
- **What would confirm it**: the specific check that proves this is the cause
- **What would disprove it**: the specific check that rules it out

Run the confirmation check before acting on the hypothesis.

### 5. Mitigation options

For each option, state:
- **Action**: exact command or code change
- **Risk**: could this make things worse?
- **Reversibility**: can it be undone immediately?
- **Time to effect**: immediate / minutes / requires deploy

Choose the option with highest reversibility and lowest risk first.

**All production-touching mitigations require explicit human approval before execution.**

### 6. Confirm mitigation

After applying mitigation:
- Check: error rate dropped to baseline?
- Check: affected users can complete the action?
- Check: no new errors introduced by the mitigation itself?
- Set a time window to monitor (5–15 minutes) before declaring resolved.

### 7. Post-incident documentation

After stabilisation, document while memory is fresh:

```
## Incident Report
Date: <date>
Duration: <start> → <end>
Status: resolved / mitigated / monitoring

## Timeline
<timestamp>: first error observed
<timestamp>: incident detected (by whom / what)
<timestamp>: investigation started
<timestamp>: mitigation applied
<timestamp>: confirmed resolved

## Impact
- Affected: <what/who>
- Scope: <all users / subset / specific condition>
- Data loss: yes / no / unknown

## Root cause
<confirmed, not hypothesis>

## Mitigation taken
<exact action>

## What prevented faster resolution
<honest assessment>

## Prevention
<what change would prevent recurrence>
```

Add to `learning-log.md`. Promote to heuristic if new pattern confirmed.

---

## Rules

- Stabilise before investigating — stop the bleeding first
- Evidence before hypothesis — never guess without data
- One hypothesis at a time — do not chase multiple theories simultaneously
- No production action without explicit human approval
- Document everything — post-incident review depends on it
- Distinguish: correlation (happened at same time) vs causation (one caused the other)

## Anti-patterns

| Anti-pattern | Risk |
|-------------|------|
| Investigating before stabilising | Extends outage duration |
| Guessing root cause without evidence | Wrong fix, wasted time |
| Multiple simultaneous mitigations | Cannot isolate which fixed it |
| No confirmation step after mitigation | Declaring resolved when it isn't |
| Not documenting because "it's resolved" | Pattern repeats; no learning captured |
| Applying irreversible fix under pressure | Makes rollback impossible |
| Fixing the symptom (restart service) without root cause | Recurs in hours |
