<!-- Generated from source/skills/bootstrap-auditor/SKILL.md. Do not edit this copy directly. Edit canonical source/skills/bootstrap-auditor/SKILL.md. -->
---
name: bootstrap-auditor
description: "Use when checking bootstrap-manifest counts, critical paths, and init-project drift against templates."
category: governance
version: 1.0.0
user-invocable: true
---

# Bootstrap auditor

## Purpose

Keep `bootstrap-manifest.json`, `verify-bootstrap-manifest.ps1`, and `init-project.ps1` outputs aligned: skill counts, `.claude` critical paths, template script lists.

## Non-goals

- Rewriting `init-project.ps1` without maintainer review.

## Inputs

- Changed skills, commands, agents, or bootstrap lists.

## Outputs

- Drift report; concrete manifest lines to bump (`exact`, `minimum`, path lists).

## Operating mode

- Default risk level: medium.
- Allowed modes: read-only verification first.
- Human approval required for: lowering counts or removing critical paths.
- Safe for autonomous execution: yes for verify; manifest edits need review.

## Procedure

1. `pwsh ./tools/verify-bootstrap-manifest.ps1`.
2. After skill add: bump `skills.exact`, `source/skills` `exact`, extend `projectBootstrap.criticalPaths` skill entries.
3. Smoke: `init-project` to temp dir per `playbooks/bootstrap-project.md` when paths change.

## Validation

- Bootstrap verify green; doc-manifest INDEX counts still match if applicable.

## Failure modes

- Skills added only to `skills-manifest` but not `source/skills` or bootstrap counts.

## Safety rules

- Do not expose secrets or paste raw tokens.
- Do not treat skipped, warn, unknown, degraded, or blocked outcomes as passed.
- Do not perform destructive actions without documented human approval.
- Do not overwrite user-local files except via declared generated targets and sync tools.

## Examples

- Add skill → set `bootstrap-manifest.json` skills.exact and each new `.claude/skills/.../SKILL.md` critical path.

## Related files

- `bootstrap-manifest.json`, `init-project.ps1`, `tools/verify-bootstrap-manifest.ps1`, `playbooks/bootstrap-project.md`
