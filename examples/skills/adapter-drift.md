# Example: adapter-drift

1. `pwsh ./tools/verify-skills-drift.ps1 -Json` reports drift for `.claude/skills/foo/SKILL.md`.
2. Run `pwsh ./tools/sync-skills.ps1 -Json` (after review), then re-run drift with `-Strict` in release gates.
