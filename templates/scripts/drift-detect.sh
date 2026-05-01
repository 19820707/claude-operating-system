#!/usr/bin/env bash
# Drift detect — session-state.md vs live git (non-blocking). H10: LF-only.
set -euo pipefail

echo "[OS-DRIFT]"

mkdir -p .claude 2>/dev/null || true

STATE=".claude/session-state.md"
DRIFT=0
TS_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo unknown)

GIT_BRANCH=""
GIT_HEAD=""
DOC_BRANCH=""
DOC_HEAD=""

if [ ! -f "$STATE" ]; then
  echo "  skip: no ${STATE}"
  echo "${TS_ISO},drift=0,git_branch=,git_head=,doc_branch=,doc_head=" >> .claude/drift.log 2>/dev/null || true
  exit 0
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "  skip: not a git repository"
  exit 0
fi

GIT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
GIT_HEAD=$(git log -1 --format="%h" 2>/dev/null || echo "")

DOC_BRANCH=$(awk -F'|' '/^\|[[:space:]]*Branch[[:space:]]*\|/ {
  gsub(/`/,"",$3); gsub(/^[ \t]+|[ \t]+$/,"",$3); print $3; exit
}' "$STATE")

DOC_HEAD=$(awk -F'|' '/^\|[[:space:]]*HEAD[[:space:]]*\|/ {
  val=$3; gsub(/`/,"",val)
  if (match(val, /[0-9a-f]{7,40}/)) print substr(val, RSTART, RLENGTH)
  exit
}' "$STATE")

GIT_FULL=$(git rev-parse HEAD 2>/dev/null || echo "")

if [ -n "$DOC_BRANCH" ] && [ -n "$GIT_BRANCH" ] && [ "$DOC_BRANCH" != "$GIT_BRANCH" ]; then
  echo "DRIFT: branch mismatch doc='${DOC_BRANCH}' git='${GIT_BRANCH}'"
  DRIFT=1
fi

if [ -n "$DOC_HEAD" ] && [ -n "$GIT_HEAD" ]; then
  if [ "$DOC_HEAD" = "$GIT_HEAD" ]; then
    echo "  head: doc matches git (${GIT_HEAD})"
  elif git merge-base --is-ancestor "$DOC_HEAD" "$GIT_FULL" 2>/dev/null; then
    UNDOC=$(git rev-list --count "${DOC_HEAD}..HEAD" 2>/dev/null || echo 0)
    UNDOC=${UNDOC:-0}
    if [ "$UNDOC" -gt 0 ] 2>/dev/null; then
      echo "DRIFT: ${UNDOC} undocumented commits (doc HEAD ${DOC_HEAD} .. git ${GIT_HEAD})"
      git log --oneline "${DOC_HEAD}..HEAD" 2>/dev/null | head -5 | sed 's/^/  /' || true
      DRIFT=1
    fi
  else
    echo "DRIFT: HEAD mismatch doc='${DOC_HEAD}' git='${GIT_HEAD}' (not ancestor chain)"
    DRIFT=1
  fi
fi

# stale: file not touched in 24h+, or file mtime older than HEAD commit (doc behind last commit)
NOW=$(date +%s 2>/dev/null || echo 0)
MT=$(stat -c %Y "$STATE" 2>/dev/null || stat -f %m "$STATE" 2>/dev/null || echo 0)
HEAD_CT=$(git log -1 --format=%ct HEAD 2>/dev/null || echo 0)
if [ "$NOW" -gt 0 ] && [ "$MT" -gt 0 ]; then
  AGE=$((NOW - MT))
  if [ "$AGE" -gt 86400 ]; then
    echo "WARN: stale session-state.md (no save in 24h+; mtime age ${AGE}s)"
  fi
fi
if [ "$HEAD_CT" -gt 0 ] && [ "$MT" -gt 0 ] && [ "$MT" -lt "$HEAD_CT" ]; then
  echo "WARN: stale session-state.md (file mtime older than HEAD commit — refresh vs git)"
fi

# WT grew vs snapshot
WT_NOW=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
WT_NOW=${WT_NOW:-0}
if [ -f ".claude/wt-snapshot.tmp" ]; then
  PREV=$(grep '^wt_count=' .claude/wt-snapshot.tmp 2>/dev/null | cut -d= -f2 || echo 0)
  PREV=${PREV:-0}
  if [ "${WT_NOW:-0}" -gt "${PREV:-0}" ] 2>/dev/null; then
    echo "WARN: WT grew (snapshot=${PREV} now=${WT_NOW})"
  fi
fi

# log line (comma-separated; strip commas from fields)
_safe() { echo "$1" | tr ',' ';'; }
echo "${TS_ISO},drift=${DRIFT},git_branch=$(_safe "${GIT_BRANCH}"),git_head=$(_safe "${GIT_HEAD}"),doc_branch=$(_safe "${DOC_BRANCH}"),doc_head=$(_safe "${DOC_HEAD}")" >> .claude/drift.log 2>/dev/null || true

exit 0
