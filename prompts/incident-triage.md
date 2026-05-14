# Prompt: incident-triage

**Model:** Opus
**Mode:** Critical → Production if mitigation touches live systems
**Output:** Impact assessment + root cause hypothesis + mitigation options

---

## Sequence

### 1. Stabilise first
- Is the incident still active?
- Is there an immediate mitigation available (feature flag, rollback, kill switch)?
- If yes and safe → apply mitigation before investigating root cause

### 2. Scope the impact
- What is broken? (service, feature, endpoint, user segment)
- How many users affected? (all, subset, specific condition)
- Since when? (first error timestamp)
- Is it getting worse, stable, or recovering?

### 3. Gather evidence
```bash
# Recent commits
git log --oneline --since="24 hours ago"

# Recent deployments (check CI/CD or deploy log)
# Recent config changes (check .env history or secrets manager)
# Error logs — extract: timestamp, error message, file:line, frequency
```

### 4. Form root cause hypothesis
- What changed recently that could cause this?
- Evidence → hypothesis (not assumption)
- State confidence: high / medium / low
- State what would confirm or disprove it

### 5. Mitigation options
For each option:
- Action: what exactly to do
- Risk: could this make things worse?
- Reversibility: can it be undone?
- Time to effect: how quickly does it help?

### 6. Post-incident
After stabilisation:
- Document timeline: what happened, when, what was done
- Root cause confirmed (not just hypothesis)
- Add to learning-log.md: what was learned, what to prevent recurrence
- Add heuristic if new pattern confirmed

---

## Output format

```
## Incident Triage
Time: <now>
Status: active / mitigated / resolved

## Impact
- Affected: <what/who>
- Since: <timestamp>
- Trend: worsening / stable / recovering

## Evidence
- <timestamp>: <error/event>

## Root cause hypothesis
- Hypothesis: <what>
- Evidence: <supporting>
- Confidence: high / medium / low

## Mitigation options
1. <action> — risk: X, reversible: yes/no, effect: immediate/minutes/hours

## Recommended action
<specific next step — requires human approval if production-touching>
```

---

## Rules

- Never touch production during incident without explicit human approval
- Mitigation before root cause — stop the bleeding first
- Evidence before hypothesis — do not guess
- Document everything — post-incident review depends on it
