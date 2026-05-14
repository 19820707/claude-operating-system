# Prompt: bootstrap-project

Use when starting a new project with the Claude operating system.
Follow `templates/new-project-bootstrap.md` for the full Phase 1/2/3 checklist.

---

## Sequence

### Phase 1 — Structure (copy templates)
```powershell
$cos = "C:\Users\<user>\claude-operating-system"
$dest = "<project-path>"

mkdir "$dest\.claude\commands"
mkdir "$dest\.claude\policies"
mkdir "$dest\.claude\agents"
mkdir "$dest\.claude\prompts"

cp "$cos\templates\project-CLAUDE.md"              "$dest\CLAUDE.md"
cp "$cos\templates\session-state.md"               "$dest\.claude\session-state.md"
cp "$cos\templates\learning-log.md"                "$dest\.claude\learning-log.md"
cp "$cos\templates\commands\session-start.md"      "$dest\.claude\commands\session-start.md"
cp "$cos\templates\commands\phase-close.md"        "$dest\.claude\commands\phase-close.md"
cp "$cos\templates\commands\system-review.md"      "$dest\.claude\commands\system-review.md"
cp "$cos\templates\commands\hardening-pass.md"     "$dest\.claude\commands\hardening-pass.md"
cp "$cos\templates\commands\release-readiness.md"  "$dest\.claude\commands\release-readiness.md"
cp "$cos\templates\commands\production-guard.md"   "$dest\.claude\commands\production-guard.md"
cp "$cos\policies\model-selection.md"              "$dest\.claude\policies\model-selection.md"
cp "$cos\policies\operating-modes.md"              "$dest\.claude\policies\operating-modes.md"
cp "$cos\policies\engineering-governance.md"       "$dest\.claude\policies\engineering-governance.md"
cp "$cos\policies\production-safety.md"            "$dest\.claude\policies\production-safety.md"
```

### Phase 2 — Context (fill in project specifics)
Open `CLAUDE.md` and fill in:
- Stack (language, framework, DB, platform)
- Branch model
- Critical surfaces (which files require Opus)
- Active roadmap

Open `.claude/session-state.md` and set:
- Branch, HEAD, Phase: "Initial setup"

Open `.claude/policies/model-selection.md` and add project-specific OPUS-MANDATORY paths.

### Phase 3 — Verify
```bash
git add CLAUDE.md .claude/
git commit -m "ops: bootstrap Claude operational system"
claude   # open Claude Code
# type: /session-start
```

Confirm `/session-start` returns clean state with correct branch and phase.

---

## Rules

- Do not skip Phase 2 — an unfilled CLAUDE.md is worse than none
- Do not commit `settings.local.json`
- Confirm `/session-start` works before starting real work
