---
name: token-economy
description: "Use when optimizing context use, reducing redundant reads, controlling validation cost, or choosing economical execution paths."
category: economy
version: 1.1.0
user-invocable: true
---

# Token Economy

Use this skill when the task can be solved with less context, fewer tool calls, cheaper validation, or a smaller blast radius.

## Operating contract

- Read selectively: start with manifests, indexes, and entry points before broad scans.
- Prefer exact source-of-truth files over duplicated summaries.
- Avoid re-reading unchanged files.
- Use dry-run and syntax checks before full execution.
- Keep outputs compact and evidence-backed.
- Default to surgical mode when the user gives a file, diff, commit, failing test, or narrow command.

## Surgical mode

Surgical mode is mandatory for named-file or small-scope tasks.

Rules:

1. Do not use `Explore`, parallel sub-agents, or repo-wide discovery by default.
2. Read only the target file(s), direct imports, direct tests, and immediate contracts needed for validation.
3. Use path-scoped commands:
   - `git diff -- <paths>`
   - `git show --stat <sha>` before full patches
   - `git status --short --branch`
4. Run targeted tests before broad suites.
5. Keep output compact: decision, files, tests, risk, next step.
6. Stop when the next safe patch is known.

Invariant: if the user names a file or short file set, broad discovery is a policy violation unless explicitly justified.

## Broad discovery gates

Broad discovery is allowed only for:

- explicit repository-wide audit;
- architecture/security/migration review;
- unknown incident scope;
- no target file/subsystem known;
- proven failure of a surgical pass;
- user-approved exploration.

When broad discovery is used, state the reason, maximum scope, and stop condition.

## Required checks

1. Identify the smallest file set that can answer or validate the task.
2. Prefer manifest-driven validation over directory-wide inference when possible.
3. Avoid dependency installation unless the touched code requires it.
4. Summarize large findings instead of dumping raw logs.
5. For named-file tasks, verify that only scoped files were read or modified.

## Invariants

- Do not spend tokens proving irrelevant facts.
- Do not run expensive validation when a cheaper deterministic check catches the same class of failure.
- Context must be proportional to risk and uncertainty.
- Economy never overrides safety-critical evidence.
- Sub-agents are not free: delegation requires a cost/risk reason.

## Non-goals

- Duplicating full policy corpora; defer to `policies/*.md` and `CLAUDE.md`.

## Inputs

- Scoped paths, failing tests, diffs, or manifest-driven validation context.

## Outputs

- Scoped reads, bounded validation, and honest status (never `skip` as pass).

## Failure modes

- Broad discovery without a gate, or economy arguments overriding safety evidence.

## Examples

- Inline procedures above illustrate intended use.

## Related files

- `skills-manifest.json`, `policies/token-economy.md` (repo root)
