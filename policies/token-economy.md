# Token Economy Policy

Minimize context cost without losing precision. Every token spent must earn its place.

This policy is binding for Claude Code, Cursor, Codex, and generic agents using Claude OS adapters.

---

## Default posture

**Default to surgical mode** when the user names a file, a small file set, a concrete diff, a specific failing test, or a narrow command.

Surgical mode means:

- no broad repository discovery;
- no `Explore` / sub-agent delegation by default;
- no repo-wide reads unless the task explicitly requires them;
- no global `git diff` when a path-scoped diff answers the question;
- no long log dumps;
- output is capped to the smallest useful report.

Use broad discovery only when the task is genuinely broad or ambiguous.

---

## Surgical mode triggers

Enter surgical mode automatically when any of these are true:

- the user provides one target file;
- the user provides a short list of files;
- the task is “fix this error”, “audit this file”, “classify this diff”, or “apply this patch”;
- a commit SHA, PR number, failing test, or exact command is provided;
- the user asks for a short answer, low-token mode, or no general discovery;
- the repository has already been discovered in the current phase.

### Surgical mode rules

1. Read only the named file(s) and direct dependencies needed to verify the change.
2. Use `git diff -- <paths>` instead of global `git diff`.
3. Use `git show --stat <sha>` before `git show <sha>`.
4. Use `git status --short --branch` instead of verbose status.
5. Prefer targeted tests over full suites.
6. Do not invoke `Explore`, parallel sub-agents, architecture scans, or directory-wide searches unless a clear blocker proves they are required.
7. If more context is needed, request or state the minimal expansion: one directory, one import chain, or one test file.
8. Keep final output under ~40 lines unless the user asks for a full report.

Invariant: **named-file task → named-file reads first**.

---

## Broad discovery allowance

Broad discovery or sub-agent exploration is allowed only when one or more apply:

- the user explicitly asks for repository-wide audit, architecture discovery, security review, or migration planning;
- no target file or subsystem is known;
- the task crosses multiple packages or runtime surfaces by design;
- impact analysis requires import graph / blast-radius analysis;
- an incident has unknown scope;
- the first surgical pass proves the issue is outside the provided files.

When broad discovery is used, the agent must state:

- why surgical mode is insufficient;
- the maximum directories/files to inspect;
- the stop condition;
- a compact summary instead of raw dumps.

---

## Reading discipline

- Define minimum relevant files before reading — never open the full repo without a concrete hypothesis.
- Read only what is strictly necessary to confirm current flow, integration point, contracts, and risk.
- For large files, read only relevant sections when the tool supports offsets/ranges.
- Summarize what was read before continuing — do not carry raw file content forward.
- Avoid re-reading unchanged files.

---

## Response discipline

- If a response can be 5x shorter without loss of precision, choose the shorter version.
- Prefer bullets and small tables over prose.
- Do not explain the obvious.
- Do not restate what the user said — act on it.
- Do not reprint full files when a diff summary suffices.
- Lead with the answer or action, not the reasoning.
- For surgical tasks, output decision + changed paths + tests + residual risk only.

---

## Log and output discipline

- Never dump long logs without triage.
- Extract only: error, file, line, failed contract, impact, and next command.
- Omit passing checks from output unless specifically requested.
- Redact secrets, PII, raw stack traces, and noisy machine output.

---

## Session length discipline

- If context grows too large, compress to a technical summary before continuing.
- Preserve: objective, evidence, decisions, risks, next steps, rollback.
- Suggest compaction proactively rather than inflating messages.
- Stop wide exploration when the next safe patch is known.

---

## Diagnosis format

Always separate:

1. **Evidence** — what was observed (file, line, output)
2. **Conclusion** — what it means
3. **Next step** — one concrete action

---

## Scope discipline

- Do not expand scope without authorisation.
- Problems found outside the current objective: register as **out of scope**, do not resolve.
- Prefer the next minimum safe reversible step.
- If a patch would touch unrelated surfaces, split it into a later task.

---

## Model and delegation economy

- Haiku/sub-agents are for cheap discovery only when discovery is allowed.
- Sonnet is for scoped implementation.
- Opus is for decisions with real architectural or security weight.
- Do not use sub-agents for a named-file patch unless the file is too large or domain-specific for the active model and the user has accepted broader cost.
- Wrong model or delegation pattern = wasted reasoning capacity + inflated cost.

---

## Anti-patterns

| Anti-pattern | Cost |
|-------------|------|
| `Explore` on a named-file task | High token waste |
| Reading entire repo before forming a hypothesis | Wasted context |
| Reprinting full files instead of diffs | Token waste |
| Global `git diff` when path-scoped diff is enough | Noise + missed focus |
| Explaining obvious steps | Noise |
| Using Opus for grep/search tasks | Model waste |
| Keeping stale context across phase boundaries | Confusion risk |
| Inflating session length instead of compacting | Context degradation |
