#!/usr/bin/env bash
# Context Drift Detector — compares .claude/session-state.md to live git.
# SessionStart / preflight: default warn-only (exit 0). Use --enforce for strict gate (exit 1 on drift).
# H10: LF-only.
set -euo pipefail

ENFORCE=0
for a in "$@"; do
  if [ "$a" = "--enforce" ]; then ENFORCE=1; fi
done

STATE=".claude/session-state.md"
if [ ! -f "$STATE" ]; then
  echo "[CONTEXT-DRIFT] skip (no ${STATE})"
  exit 0
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "[CONTEXT-DRIFT] skip (not a git repository)"
  exit 0
fi

GIT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
GIT_FULL=$(git rev-parse HEAD 2>/dev/null || echo "")
GIT_SHORT=$(git rev-parse --short HEAD 2>/dev/null || echo "")

# Markdown pipe table: | Branch | value |
SESSION_BRANCH=$(awk -F'|' '/^\|[[:space:]]*Branch[[:space:]]*\|/ {
  gsub(/`/,"",$3); gsub(/^[ \t]+|[ \t]+$/,"",$3); print $3; exit
}' "$STATE")

# | HEAD | `abc1234` subject | — first git-like hash in value column
SESSION_HEAD=$(awk -F'|' '/^\|[[:space:]]*HEAD[[:space:]]*\|/ {
  val=$3
  gsub(/`/,"",val)
  if (match(val, /[0-9a-f]{7,40}/)) print substr(val, RSTART, RLENGTH)
  exit
}' "$STATE")

DRIFT=0

trim_empty() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  echo -n "$s"
}

SESSION_BRANCH=$(trim_empty "$SESSION_BRANCH")
SESSION_HEAD=$(trim_empty "$SESSION_HEAD")

echo "[CONTEXT-DRIFT]"
if [ -n "$SESSION_BRANCH" ] && [ -n "$GIT_BRANCH" ] && [ "$SESSION_BRANCH" != "$GIT_BRANCH" ]; then
  echo "  branch: doc='${SESSION_BRANCH}' git='${GIT_BRANCH}' -> MISMATCH"
  DRIFT=1
else
  echo "  branch: doc='${SESSION_BRANCH:-<empty>}' git='${GIT_BRANCH:-<empty>}' -> OK"
fi

if [ -n "$SESSION_HEAD" ] && [ -n "$GIT_FULL" ]; then
  if [ "$GIT_FULL" = "$SESSION_HEAD" ] || [ "$GIT_SHORT" = "$SESSION_HEAD" ]; then
    UNDOC=$(git rev-list --count "${SESSION_HEAD}..HEAD" 2>/dev/null || echo 0)
    echo "  head:   doc='${SESSION_HEAD}' matches git tip (${GIT_SHORT}) commits_since_doc=${UNDOC}"
  elif git merge-base --is-ancestor "$SESSION_HEAD" "$GIT_FULL" 2>/dev/null; then
    UNDOC=$(git rev-list --count "${SESSION_HEAD}..HEAD" 2>/dev/null || echo 0)
    echo "  head:   doc='${SESSION_HEAD}' is ancestor of git='${GIT_SHORT}' commits_since_doc=${UNDOC}"
    if [ "${UNDOC}" != "0" ] && [ -n "${UNDOC}" ]; then
      echo "  note:   ${UNDOC} commit(s) after documented HEAD — update session-state if intentional"
    fi
  else
    echo "  head:   doc='${SESSION_HEAD}' git='${GIT_SHORT}' -> MISMATCH (not same tip / not ancestor)"
    DRIFT=1
  fi
else
  echo "  head:   doc='${SESSION_HEAD:-<empty>}' git='${GIT_SHORT:-<empty>}' -> SKIP (fill session-state Identificação table)"
fi

if [ "$DRIFT" -eq 1 ]; then
  echo "[CONTEXT-DRIFT] DRIFT DETECTED — reconcile session-state.md with git before high-risk work"
  if [ "$ENFORCE" -eq 1 ]; then
    exit 1
  fi
fi

exit 0
