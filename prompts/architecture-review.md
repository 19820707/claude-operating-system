# Prompt: architecture-review

**Model:** Opus
**Mode:** Fast → escalate if structural changes proposed
**Output:** System reading + risk map + improvement proposals

---

## Sequence

### 1. Map the real architecture
- List all modules/packages with their responsibilities
- Identify entry points (API routes, CLI, event consumers)
- Identify data flows (request → handler → service → DB → response)
- Identify external dependencies (third-party APIs, queues, storage)
- Identify shared state and side-effect surfaces

### 2. Identify boundaries and coupling
- Where are the module boundaries? Are they respected?
- What are the implicit contracts (undocumented assumptions)?
- Where is logic duplicated across modules?
- What would break if module X changed its interface?

### 3. Identify structural risks
For each finding:
- **Evidence:** file:line or pattern observed
- **Risk:** what could go wrong
- **Severity:** critical / high / medium / low
- **Reversible fix available:** yes / no

### 4. Propose improvements
- Only evidence-based proposals
- Each proposal: smallest change that reduces the risk
- Ordered by: value × reversibility × blast radius

---

## Output format

```
## Architecture Reading
- [module]: [responsibility] — [coupling observations]

## Critical Flows
- [flow name]: [path from entry to exit]

## Structural Risks
| Risk | Evidence | Severity | Fix |
|------|---------|----------|-----|

## Proposals (ordered)
1. [smallest valuable change] — risk reduced: X, effort: Y, rollback: Z
```

---

## Rules

- Do not propose changes to auth/billing/migrations without Critical mode
- Do not propose broad rewrites — prefer seam extraction and incremental evolution
- Do not invent structure — only what is in the code
- State explicitly what was NOT read and why
