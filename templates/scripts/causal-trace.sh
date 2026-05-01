#!/usr/bin/env bash
# Causal Chain Tracker — finds decision IDs D-NNN in git history for a commit or path. H10: LF-only.
set -euo pipefail

echo "[OS-CAUSAL-TRACE]"

COMMIT="HEAD"
PATHSPEC=""

while [ $# -gt 0 ]; do
  case "$1" in
    --path=*)
      PATHSPEC="${1#--path=}"
      shift
      ;;
    --path)
      PATHSPEC="${2:-}"
      shift 2
      ;;
    --help|-h)
      echo "Usage: bash causal-trace.sh [COMMIT|RANGE] [--path=relative/path.ts]"
      echo "  Examples:"
      echo "    bash causal-trace.sh HEAD"
      echo "    bash causal-trace.sh abc1234 --path=server/middleware/auth.ts"
      exit 0
      ;;
    *)
      COMMIT="$1"
      shift
      ;;
  esac
done

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "  skip: not a git repository"
  exit 0
fi

if ! git rev-parse "$COMMIT" >/dev/null 2>&1; then
  echo "  skip: invalid commit/ref: $COMMIT"
  exit 0
fi

echo "  commit/ref: $COMMIT"
if [ -n "$PATHSPEC" ]; then
  echo "  path       : $PATHSPEC"
fi

# Messages mentioning D- digits (commit messages / bodies)
if [ -n "$PATHSPEC" ]; then
  MSGS=$(git log -n 60 --format=%B "$COMMIT" -- "$PATHSPEC" 2>/dev/null | grep -oE 'D-[0-9]+' | sort -u | head -20 || true)
else
  MSGS=$(git log -n 60 --format=%B "$COMMIT" 2>/dev/null | grep -oE 'D-[0-9]+' | sort -u | head -20 || true)
fi

if [ -f ".claude/session-state.md" ]; then
  SS=$(grep -oE 'D-[0-9]+' .claude/session-state.md 2>/dev/null | sort -u | head -20 || true)
  if [ -n "${SS}" ]; then
    echo "  session-state.md references:"
    echo "${SS}" | sed 's/^/    /'
  fi
fi

if [ -n "$PATHSPEC" ]; then
  echo "  commits (subject) mentioning D-NNN for path:"
  git log -n 25 --grep='D-[0-9][0-9]*' --extended-regexp --format='%h %s (%ci)' "$COMMIT" -- "$PATHSPEC" 2>/dev/null | sed 's/^/    /' || true
else
  echo "  commits (subject) mentioning D-NNN:"
  git log -n 25 --grep='D-[0-9][0-9]*' --extended-regexp --format='%h %s (%ci)' "$COMMIT" 2>/dev/null | sed 's/^/    /' || true
fi

if [ -z "${MSGS}" ]; then
  echo "  (no D-NNN in recent commit bodies for this scope — subjects may still list IDs above)"
  echo "  hint: reference decisions in commits, e.g. chore(auth): rate limit D-043"
  exit 0
fi

echo "  decision ids in recent commit bodies:"
echo "${MSGS}" | sed 's/^/    /'

SUBJ=$(git log -1 --format='%h %s' "$COMMIT" 2>/dev/null || true)
echo "  tip-of-ref : ${SUBJ}"

exit 0
