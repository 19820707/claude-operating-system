# Stack profile (example)

When you run `init-project.ps1 -Profile node-ts-service` (or `react-vite-app`), the OS copies `templates/profiles/<Profile>.md` to **`.claude/stack-profile.md`**.

This file is a **stand-in**: it documents TypeScript service defaults (lint, test, build) without referencing any private repository URL.

## Example expectations

- Strict TypeScript and test gates before merge.
- Use `bash .claude/scripts/ts-error-budget.sh` after bootstrap to set a baseline on real repos.
