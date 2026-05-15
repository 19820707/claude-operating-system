<!-- Engineering OS — ../../CLAUDE.md + ../../.agents/OPERATING_CONTRACT.md -->
<!-- Invariant: bootstrap = establish OS baseline before any product work. -->
<!-- Never: skip session-state.md or learning-log.md templates on a cold repo. -->
<!-- Fail closed: repo without CLAUDE.md -> create from template, confirm invariants before editing code. -->

# /bootstrap-project

Bootstrap or restore the Engineering OS in a repo that has no (or broken) OS baseline.

## When to use

- Cold repo: no `.claude/` directory or empty CLAUDE.md
- OS drift: contract tests failing, policies stale
- Post-merge reset: `.claude/` lost after rebase

## Sequence

1. Check existing CLAUDE.md + .claude/ for what is present vs missing
2. Create / restore: session-state.md, learning-log.md, heuristics/operational.md
3. Align settings.json (approvalPolicy, allow/deny, hooks)
4. Copy scripts from `templates/scripts/` to `.claude/scripts/` (LF-only)
5. Run contract tests: `npx vitest run tests/claude-*-contract.test.ts`
6. Declare OS operational or escalate remaining gaps

## OS health checklist

- CLAUDE.md exists with invariants + critical surfaces
- .agents/OPERATING_CONTRACT.md present
- .claude/session-state.md present and not stale (> 7 days)
- .claude/settings.json valid (npm run check + npx vitest run in allow)
- .claude/scripts/preflight.sh LF-only
- Contract tests green: npx vitest run tests/claude-*
