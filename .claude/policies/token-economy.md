# Token Economy Policy

Minimize context cost without losing precision.
Every token spent must earn its place.

---

## Reading discipline

- Define minimum relevant files before reading — never open the full repo without a concrete hypothesis
- Read only what is strictly necessary to confirm: current flow, integration point, contracts, risk
- For large files, read only the relevant section (offset + limit)
- Summarize what was read before continuing — do not carry raw file content forward

## Response discipline

- If a response can be 5x shorter without loss of precision → choose the shorter version
- Prefer bullets and small tables over prose
- Do not explain the obvious
- Do not restate what the user said — act on it
- Do not reprint full files when a diff summary suffices
- Lead with the answer or action, not the reasoning

## Log and output discipline

- Never dump long logs without triage
- Extract only: error + file + line + failed contract + impact
- Omit passing checks from output unless specifically requested

## Session length discipline

- If context grows too large → compress to a technical summary before continuing
- Preserve: objective / evidence / decisions / risks / next steps / rollback
- Suggest compaction proactively rather than inflating messages

## Diagnosis format

Always separate:
1. **Evidence** — what was observed (file, line, output)
2. **Conclusion** — what it means
3. **Next step** — one concrete action

## Scope discipline

- Do not expand scope without authorisation
- Problems found outside the current objective → register as "out of scope", do not resolve
- Prefer next minimum safe reversible step

## Model economy

- Haiku for discovery, search, reads, triagem — do not use Sonnet/Opus for these
- Sonnet for scoped implementation — do not escalate to Opus without demonstrable need
- Opus for decisions with real architectural or security weight
- Wrong model = wasted reasoning capacity + inflated cost

## Anti-patterns

| Anti-pattern | Cost |
|-------------|------|
| Reading entire repo before forming a hypothesis | Wasted context |
| Reprinting full files instead of diffs | Token waste |
| Explaining obvious steps | Noise |
| Using Opus for grep/search tasks | Model waste |
| Keeping stale context across phase boundaries | Confusion risk |
| Inflating session length instead of compacting | Context degradation |
