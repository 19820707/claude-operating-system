# Autonomous repair (bounded)

## Purpose

Run **validation-first**, **reversible** repair workflows against the repo under autonomy policy **A3**, using `tools/os-autopilot.ps1` and `policies/autonomy-policy.json`. Escalate to human steward approval when the work crosses any `requiresHumanApproval.surfaces` entry.

## Trigger conditions

- Local drift in docs, adapters, manifests, or examples is suspected.
- `os-validate` quick/standard has failed or warned, and the hypothesis is non-destructive.

## Required inputs

- Branch with diff-friendly commits.
- `policies/autonomy-policy.json` and `docs/AUTONOMY.md` read by the operator or agent.
- Optional: `append-approval-log` row if the repair later touches steward surfaces.

## Risk level

**Medium** — may touch generated targets and documentation; **not** for production mutation.

## Required approvals

None for **read-only validation** and **dry-run** phases. If execution crosses **Release**, **Production**, **Migration**, **Destructive**, **Critical**, or **Incident** steward classes, follow **`docs/APPROVALS.md`** and record ledger lines before mutating.

## Preflight checks

- `pwsh ./tools/verify-autonomy-policy.ps1` passes (add `-Strict` before release-class work).
- Working tree is on a **feature branch** (not silent default-branch pushes).

## Execution steps

1. Run `pwsh ./tools/os-autopilot.ps1 -Goal "<hypothesis>" -Profile quick -DryRun -Json` and inspect `requiresApproval` / `approvalReasons`.
2. If not blocked, deepen to `standard` / `strict` only when justified.
3. Apply only **governed, reversible** edits (diff visible); never bypass validators or relax policy in-repo without human approval.

## Validation steps

- `pwsh ./tools/os-validate.ps1 -Profile quick -Json` then escalate profile if needed.
- `pwsh ./tools/verify-autonomy-policy.ps1 -Strict -Json` before merge/release contexts.

## Rollback / abort criteria

- Abort if autopilot status is **blocked** or **fail**, or if `requiresApproval` is true and no ledger approval exists.
- Roll back via `git revert` / branch reset per `policies/rollback-policy.md`.

## Evidence to collect

- Autopilot JSON (`os-autopilot.ps1 -Json`); optional JSONL via `-WriteEvidence`.
- Validator envelopes from `os-validate` / `verify-os-health` as appropriate.

## Expected outputs

- Green validation at the chosen profile **with `ok` aggregate status** (not `warn`/`skip` passed off as success).
- Diffs and notes explaining what changed and why.

## Failure reporting

- File issues with envelope JSON attached; do not downgrade `fail` to `warn` in summaries.

## Approval ledger

Not required for local validation-only loops. Required when steward tags apply (see **Required approvals**).

## Related

- `docs/AUTONOMY.md`, `source/skills/autonomous-runtime/SKILL.md`, `docs/CAPACIDADES-OPERACIONAIS.md` §17
