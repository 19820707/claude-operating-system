---
name: multi-agent-coordination
description: "Use when multiple agents, worktrees, sessions, or humans may touch overlapping files, modules, decisions, or responsibilities."
category: coordination
version: 1.0.0
user-invocable: true
---

# Multi-Agent Coordination

Use this skill to prevent collisions between concurrent agents, parallel worktrees, or repeated sessions operating on the same system.

## Operating contract

- Claim ownership before editing shared or risky surfaces.
- Record intentions and shared decisions before irreversible work.
- Detect overlapping paths, stale leases, and conflicting assumptions.
- Release claims when work completes or is abandoned.
- Prefer coordination evidence over conversational memory.

## Required checks

1. Identify touched paths and shared modules.
2. Check active leases or intentions in `.claude/agent-state.json` when available.
3. Run `bash .claude/scripts/coordination-check.sh` when coordination risk exists.
4. Append relevant decisions before cross-agent handoff.
5. Release or update ownership after completion.

## Invariants

- Two agents must not independently mutate the same critical surface without coordination.
- Claims expire or are explicitly released.
- Shared decisions must be inspectable after session compaction.
- Coordination state is operational evidence, not decoration.

## Safety rules

- Do not expose secrets in coordination logs or handoff text.
- Do not treat skipped, warn, unknown, degraded, or blocked outcomes as passed.
- Do not perform destructive shared-surface work without explicit coordination and approval.
- Do not overwrite user-local files outside claimed paths.

## Non-goals

- Duplicating full policy corpora; defer to `policies/*.md` and `CLAUDE.md`.

## Inputs

- Agent roles, touched paths, and coordination artifacts in `.claude/`.

## Outputs

- Claims, releases, and evidence with explicit status taxonomy.

## Failure modes

- Stale leases, overlapping writes, or unlabeled concurrent edits.

## Examples

- Inline procedures above illustrate intended use.

## Related files

- `skills-manifest.json`, `policies/engineering-governance.md` (repo root)
