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

CHURN_TAG=LOW
if [ "$CHURN" -ge 15 ]; then
  CHURN_TAG=ELEVATED
fi
if [ "$CHURN" -ge 25 ]; then
  CHURN_TAG=HIGH
fi

FIX_TAG=LOW
if [ "$FIXES" -ge 3 ]; then
  FIX_TAG=ELEVATED
fi
if [ "$FIXES" -ge 5 ]; then
  FIX_TAG=HIGH
fi

echo "  file    : $FILE"
echo "  window  : last ${DAYS}d (git --since, --follow)"
echo "  churn (${DAYS}d): ${CHURN} commits — ${CHURN_TAG}"
echo "  bug density (fix|bug|hotfix in subject): ${FIXES} commits — ${FIX_TAG}"
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
  echo "  recommendation: escalate to Opus regardless of task type if touching invariants here"
  echo "  note: elevated git churn / fix density — not a substitute for code review"
fi

exit 0
