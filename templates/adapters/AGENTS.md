# AGENTS.md — Codex / generic agents (Claude OS Runtime)

This project uses **Claude OS Runtime**. The operational source of truth is **`.claude/`** — not this file.

## Mission

Act as a bounded engineering agent: make the smallest safe change that satisfies the task, preserve project invariants, validate deterministically, and leave an auditable handoff.

Do not behave like a repo crawler unless the task is explicitly repo-wide.

## Before you edit

Read, in order:

1. **`CLAUDE.md`** — project-level policy and how Claude Code expects work to run.
2. **`.claude/session-state.md`** — branch, decisions, risks, next steps (do not assume chat history).
3. **`.claude/workflow-manifest.json`** — phase gates for this repo.
4. **`.claude/os-capabilities.json`** — capability routing and automation boundaries.

Then classify the task:

| Task shape | Mode | Default action |
|------------|------|----------------|
| Named file / small file set / failing test / concrete diff | Surgical | Read only named paths + direct dependencies |
| Unknown bug scope | Diagnostic | Start narrow; expand one dependency ring at a time |
| Architecture/security/release review | Broad | State scope, stop condition, and evidence plan |
| Auth/security/CI/release/filesystem/production/payments | Critical | **human approval required** before mutation |

## Execution protocol

1. **Confirm scope** — target files, expected behavior, forbidden surfaces.
2. **Read narrowly** — target files first; direct imports/tests only when needed.
3. **State invariants** — what must not change.
4. **Patch surgically** — no opportunistic cleanup, no unrelated formatting churn.
5. **Validate proportionally** — targeted tests first, then broader checks only if risk warrants.
6. **Report evidence** — changed files, tests, residual risks, rollback.

Stop and ask when the next step would exceed scope, touch a critical surface, or require destructive git/filesystem actions.

## Token economy / surgical mode

If the task names a file, a small file set, a commit, a failing test, or a concrete diff, use **surgical mode**:

- Do **not** run broad repository discovery.
- Do **not** use `Explore` / sub-agents unless the user explicitly asks or the scoped pass proves it is required.
- Read only target files, direct imports, direct tests, and immediate contracts.
- Prefer `git diff -- <paths>` over global `git diff`.
- Prefer targeted tests over full suites.
- Keep summaries short: decision, files, tests, risk, next step.

Broad discovery is reserved for explicit architecture/security/repo-wide audits, unknown incident scope, or user-approved exploration.

## Quality bar

Every non-trivial patch must improve at least one of:

- correctness;
- safety / fail-closed behavior;
- observability without leaking secrets;
- testability;
- maintainability by removing proven duplication or clarifying contracts.

Do **not** add abstractions, dependencies, or new runtime surfaces without measurable benefit.

## Validation ladder

Use the cheapest reliable validation first:

1. Syntax/type check for touched files when available.
2. Targeted unit/integration tests for changed behavior.
3. Contract/schema validators when manifests or runtime policy changed.
4. Full suite only for broad or high-risk changes.

If validation cannot run, report the exact blocker and the most relevant command for the human to run.

## Output contract

For implementation tasks, final output must include:

- changed files;
- behavior before/after;
- tests run and result;
- residual risks;
- rollback command or revert plan;
- **human approval required** if any critical surface was touched.

Do not paste raw logs, long stack traces, secrets, tokens, PII, or full JSON dumps.

## Commands to prefer (installed under `.claude/scripts/`)

- **Prime (bounded context):**
  `pwsh .claude/scripts/session-prime.ps1`
- **Route a task:**
  `pwsh .claude/scripts/route-capability.ps1 -Query "<task>"`
- **Workflow status:**
  `pwsh .claude/scripts/workflow-status.ps1 -Phase verify`
- **Close session:**
  `pwsh .claude/scripts/session-digest.ps1 -Summary "<summary>" -Outcome passed`

Also use **session-absorb** during work when you learn something durable:
`pwsh .claude/scripts/session-absorb.ps1 -Note "<note>" -Kind ops`

## Git and safety (hard negatives)

- Do **not** use `git add .`, `git push --force`, or `git reset --hard` without explicit human direction.
- Do **not** run `git stash pop` automatically — review `git stash show` first; never apply stash without human review of the diff.
- Do **not** delete backups or whole directories without human review.
- Do **not** expose secrets, PII, raw stack traces, or raw log dumps in chat, commits, or session files.

## human approval required

**human approval required** before changes to auth, security, CI, release, filesystem layout, permissions, production systems, or payments — and whenever policy says so.

See **`.agent/runtime.md`**, **`.agent/handoff.md`**, and **`.agent/operating-contract.md`** for the shared neutral contract.
