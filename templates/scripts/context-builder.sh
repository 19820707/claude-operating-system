#!/usr/bin/env bash
# Suggested context read order when salience tooling is unavailable. Exit 0; LF-only.
set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

echo "[OS-CONTEXT] fallback read order (sequential evidence — not a substitute for salience layers):"
echo "  1. ~/.claude/CLAUDE.md (if exists)"
echo "  2. ${REPO_ROOT}/CLAUDE.md"
echo "  3. ${REPO_ROOT}/.claude/session-state.md"
echo "  4. ${REPO_ROOT}/.claude/learning-log.md"
echo "  5. ${REPO_ROOT}/.claude/settings.json (hooks / permissions only)"
echo "Then: bash .claude/scripts/salience-score.sh --digest  (when available)"

exit 0
