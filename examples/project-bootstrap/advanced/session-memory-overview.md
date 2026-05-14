# Session memory (post-bootstrap)

| Artifact | Purpose |
|----------|---------|
| `.claude/session-state.md` | Branch/HEAD, phase, objective, handoff table. |
| `.claude/learning-log.md` | Phase-close cumulative learning. |
| `.claude/decision-log.jsonl` | Append-only JSONL; each line matches `decision-log.schema.json`. |
| `.claude/settings.json` | Permissions / hooks (no secrets). |
| `decision-log.schema.json` | Copied from OS `templates/local/` for local validation. |

Hooks and scripts under `.claude/scripts/` read/write bounded artifacts (indexes, reports) — see `bootstrap-manifest.json` script list.
