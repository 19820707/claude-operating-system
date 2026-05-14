# Prompt: task-classify

Use at the start of any task to select the right model, mode, and approach before acting.

---

## Classification sequence

### Step 1 — Task type
Which of these best describes the task?

| Type | Description |
|------|-------------|
| `discovery` | Read, search, explore, map — no changes |
| `decision` | Architecture, design, tradeoff — no changes yet |
| `implementation` | Write or modify code, config, or docs |
| `validation` | Run checks, tests, verify state |
| `rollback` | Undo a previous change |
| `incident` | Active problem in production or staging |
| `audit` | Security, compliance, or quality review |

### Step 2 — Critical surface check
Does this task touch any of these?

| Surface | File → |
|---------|--------|
| auth / entitlement | `critical-surfaces/auth.md` |
| billing / payments | `critical-surfaces/billing.md` |
| migrations | `critical-surfaces/migrations.md` |
| deploy / production | `critical-surfaces/deploy.md` |
| PII / sensitive data | `critical-surfaces/pii.md` |

If yes → **Critical mode, Opus mandatory, explicit approval required.**

### Step 3 — Model selection

| Condition | Model |
|-----------|-------|
| discovery / grep / reads | Haiku |
| implementation (non-critical) | Sonnet |
| decision / architecture / critical surface | Opus |
| incident response | Opus |

### Step 4 — Output

```
Task type:     <type>
Critical:      yes / no — <surface if yes>
Mode:          Fast / Critical / Production
Model:         Haiku / Sonnet / Opus
Minimum files: <list>
Next action:   <one concrete step>
Approval needed: yes / no
```

---

## Rules

- If uncertain about critical surface → default to Opus
- Never start implementation before classification
- If task touches multiple surfaces → classify at the highest risk level
