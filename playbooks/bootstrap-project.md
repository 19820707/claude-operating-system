# Playbook: Bootstrap project

## Purpose

Create a new project workspace from Claude OS templates with deterministic validation and no silent overwrites.

## Trigger conditions

- New repository or folder needs `.claude/` (and adapters) initialized from this OS repo.

## Required inputs

- Target project path, optional `-SkipGitInit`, and policy on overwriting existing files.

## Risk level

**Medium** — filesystem writes and scaffold correctness.

## Required approvals

- Not required for local dry-runs; human confirmation before writing into an existing populated project.

## Preflight checks

- Run `pwsh ./init-project.ps1 -ProjectPath <path> -DryRun -SkipGitInit` and review the planned file list.
- Confirm target path is not production or shared without backup.

## Execution steps

1. Run `init-project.ps1` with agreed flags.
2. Run `pwsh ./tools/verify-bootstrap-manifest.ps1` if templates or counts changed upstream.
3. Smoke critical paths listed in `bootstrap-manifest.json` for the scaffold.

## Validation steps

- Project-local scripts return JSON with non-failing status for docs query and capability route smoke tests when applicable.

## Rollback / abort criteria

- Abort if dry-run shows unexpected overwrites; delete partial scaffold only if safe and empty of user data.

## Evidence to collect

- Command log, path of scaffold, and any validation JSON snippets for the ticket.

## Expected outputs

- Populated `.claude/` tree, adapters, and documented next steps for the team.

## Failure reporting

- Capture init-project exit code and tail of stderr; do not claim success if validation smoke failed.
