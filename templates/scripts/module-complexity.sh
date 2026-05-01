#!/usr/bin/env bash
# Predictive Phase Classifier — git-history signals for a path (churn / fix density / authors). H10: LF-only.
set -euo pipefail

echo "[OS-COMPLEXITY]"

DAYS=90
FILE=""
for a in "$@"; do
  case "$a" in
    --days=*)
      DAYS="${a#--days=}"
      ;;
    --help|-h)
      echo "Usage: bash module-complexity.sh [--days=N] <file>"
      exit 0
      ;;
    *)
      [ -z "$FILE" ] && FILE="$a"
      ;;
  esac
done

if [ -z "$FILE" ]; then
  echo "  usage: bash module-complexity.sh [--days=90] path/to/file.ts"
  exit 0
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "  skip: not a git repository"
  exit 0
fi

SINCE="${DAYS} days ago"
FILE=$(echo "$FILE" | tr '\\' '/')

CHURN=$(git log --since="$SINCE" --oneline --follow -- "$FILE" 2>/dev/null | wc -l | tr -d ' ')
CHURN=${CHURN:-0}
FIXES=$(git log --since="$SINCE" --oneline --follow --grep='fix' --grep='bug' --grep='hotfix' --regexp-ignore-case -- "$FILE" 2>/dev/null | wc -l | tr -d ' ')
FIXES=${FIXES:-0}
AUTHORS=$(git log --since="$SINCE" --format='%ae' --follow -- "$FILE" 2>/dev/null | sort -u | wc -l | tr -d ' ')
AUTHORS=${AUTHORS:-0}

echo "  file    : $FILE"
echo "  window  : last ${DAYS}d (git --since)"
echo "  churn   : ${CHURN} commits"
echo "  fix-like: ${FIXES} commits (grep fix|bug|hotfix in subject)"
echo "  authors : ${AUTHORS} unique emails"

RISK=LOW
if [ "$CHURN" -ge 15 ] || [ "$FIXES" -ge 3 ]; then
  RISK=ELEVATED
fi
if [ "$CHURN" -ge 25 ] || [ "$FIXES" -ge 5 ]; then
  RISK=HIGH
fi

echo "  historical risk (heuristic): ${RISK}"
if [ "$RISK" != "LOW" ]; then
  echo "  recommendation: treat edits as higher-risk; consider Opus / deeper review regardless of task label"
fi

exit 0
