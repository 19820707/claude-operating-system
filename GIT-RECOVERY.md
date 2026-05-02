# Git recovery — Claude OS repo

Safe patterns when Git is blocked, dirty, or mid-operation. This repo treats **human review** as mandatory before destructive commands.

## Fetch first / non-fast-forward push

1. Inspect: `git status -sb` and `pwsh ./tools/verify-git-hygiene.ps1 -Json`
2. Integrate remote safely: `git pull --rebase` (resolve conflicts consciously; do not `git rebase --skip` unless you intend to drop commits)
3. Re-run: `pwsh ./tools/os-validate-all.ps1 -Strict`
4. Push without rewriting history: `git push` (never `git push --force` on shared branches)

## Rebase conflict

1. `git status` — list unmerged paths
2. Resolve files, then `git add <each resolved file>`
3. Continue: `git rebase --continue`
4. Avoid `git rebase --abort` unless you deliberately discard the in-progress rebase (explain why in session notes)

## Nested clone folder (`claude-operating-system/` under repo root)

- **Never** `git add .` while that folder exists
- Inspect: `Get-ChildItem .\claude-operating-system -Force` and `Test-Path .\claude-operating-system\.git`
- After human review only: remove (`Remove-Item -Recurse -Force .\claude-operating-system`) or move outside the repo (backup). **Never** delete automatically from scripts or agents.
- The repo lists `/claude-operating-system/` in `.gitignore` to reduce accidental tracking; `verify-git-hygiene.ps1` still detects a physical nested clone on disk.
- **Severity:** `pwsh ./tools/verify-git-hygiene.ps1` alone reports a **WARN** locally so health can surface the risk before `git add .`. With **`-Strict`** (as used by `pwsh ./tools/os-validate-all.ps1 -Strict` and CI), the same condition is a **FAIL** until the folder is removed or moved. **CI** (`CI` / `GITHUB_ACTIONS`) always treats a dirty tree or nested clone as **FAIL**.

## Stash

- List: `git stash list` / `git stash show --stat stash@{0}`
- **Do not** `git stash pop` without reading the diff first
- Prefer `git stash apply` when you need a reversible trial

## Forbidden without explicit approval / review

- `git push --force` (and `--force-with-lease` on shared default branches)
- `git reset --hard`
- `git add .` (prefer `git add <path>` …)
- `git stash pop` without reviewing `stash show`

## Verifiers

- `pwsh ./tools/verify-git-hygiene.ps1` — read-only Git state (rebase, merge, markers, nested `.git`, nested `claude-operating-system/`, dirty in CI); add `-Strict` for release-style blocking checks
- `pwsh ./tools/verify-os-health.ps1` — full OS health including git hygiene

**human approval required** for policy changes, CI, and anything that alters protected branches or production gates.
