---
name: token-economy
description: "Use when optimizing context use, reducing redundant reads, controlling validation cost, or choosing economical execution paths."
category: economy
version: 1.0.0
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

## Required checks

1. Identify the smallest file set that can answer or validate the task.
2. Prefer manifest-driven validation over directory-wide inference when possible.
3. Avoid dependency installation unless the touched code requires it.
4. Summarize large findings instead of dumping raw logs.

## Invariants

- Do not spend tokens proving irrelevant facts.
- Do not run expensive validation when a cheaper deterministic check catches the same class of failure.
- Context must be proportional to risk and uncertainty.
- Economy never overrides safety-critical evidence.
