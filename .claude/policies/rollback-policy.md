# Rollback Policy

Every change must have an explicit, executable rollback path defined before execution.
No rollback defined = change is not ready.

---

## Principle

Reversibility is a first-class constraint, not an afterthought.
The rollback path must be stated before approval, not improvised after failure.

---

## Rollback requirement by change type

| Change type | Rollback method | Approval required |
|-------------|----------------|-------------------|
| File edits (non-critical) | `git checkout HEAD -- <file>` | No |
| New files | `git rm <file>` or `git revert` | No |
| Commit (local) | `git revert <hash> --no-edit` | No |
| Commit (pushed) | `git revert <hash> --no-edit && git push` | Confirm before push |
| Schema migration (additive) | Additive columns are safe; rollback = no-op or manual drop | Document explicitly |
| Schema migration (destructive) | **Requires explicit approval + backup confirmation** | Yes |
| Dependency change | `git checkout HEAD -- package.json && npm install` | Confirm |
| Config change (.env, secrets) | **Never autonomous** | Always |
| Deploy / production | **Never autonomous** | Always — human gate |
| Auth / billing / publish logic | Revert commit + redeploy | Yes — Critical mode |

---

## Required rollback statement

Every pre-implementation plan must include:

```
**Rollback:**
<exact command or procedure to undo this change>
```

Every execution result must include:

```
**Rollback:**
<updated command reflecting what was actually done>
```

---

## Rollback execution rules

1. Before executing rollback, confirm the target state is known (run `git log --oneline -5`)
2. Never rollback using `git reset --hard` without explicit user approval
3. Never force-push without explicit user approval
4. For pushed commits → use `git revert` (preserves history) not `git reset`
5. For destructive operations (drop table, delete files) → confirm with user before executing
6. After rollback → run the same validation checks as after the original change

---

## Rollback anti-patterns

| Anti-pattern | Risk |
|-------------|------|
| "Rollback: manually revert" without exact command | Unusable under pressure |
| Using `git reset --hard` without approval | Destroys unpushed commits |
| Force-pushing to shared branch | Overwrites others' work |
| No rollback defined for schema migrations | Irreversible data loss risk |
| Rollback defined after change, not before | Too late if change fails mid-execution |

---

## Staged rollback for multi-file changes

When a change touches multiple files:

```
# Granular rollback (per file)
git checkout HEAD -- <file1> <file2>

# Full commit rollback
git revert <commit-hash> --no-edit

# Nuclear (local only, never pushed)
git reset --soft HEAD~1   # keeps changes staged
```

State which level of rollback is available and appropriate before starting.
