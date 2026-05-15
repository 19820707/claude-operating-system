#!/usr/bin/env bash
# secret-redact.sh — Detect and redact secret patterns in files or stdin
# Modes: --scan <file> | --pipe | --check <file>
# Exit codes: --check exits 1 if secrets found; --scan/--pipe always exit 0
# LF-only

set -euo pipefail

# Combined detection pattern (grep -E)
DETECT_PATTERN='[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}|railway_[A-Za-z0-9]{20,}|gh[ps]_[A-Za-z0-9]{36,}|sk_live_[A-Za-z0-9]{24,}|(api[_-]?key|secret|token)[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{20,}'

_redact_stream() {
  sed -E \
    -e 's/[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/[REDACTED-UUID_V4]/g' \
    -e 's/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/[REDACTED-JWT]/g' \
    -e 's/railway_[A-Za-z0-9]{20,}/[REDACTED-RAILWAY_TOKEN]/g' \
    -e 's/gh[ps]_[A-Za-z0-9]{36,}/[REDACTED-GITHUB_TOKEN]/g' \
    -e 's/sk_live_[A-Za-z0-9]{24,}/[REDACTED-STRIPE_KEY]/g' \
    -e 's/((api[_-]?key|secret|token)[[:space:]]*[:=][[:space:]]*)[A-Za-z0-9_-]{20,}/\1[REDACTED-API_KEY]/g'
}

MODE="${1:-}"
case "$MODE" in
  --scan)
    FILE="${2:-}"
    if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
      echo "ERROR: --scan requires a valid file path" >&2
      exit 1
    fi
    grep -En "$DETECT_PATTERN" "$FILE" 2>/dev/null | _redact_stream || true
    ;;

  --pipe)
    _redact_stream
    ;;

  --check)
    FILE="${2:-}"
    if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
      echo "ERROR: --check requires a valid file path" >&2
      exit 1
    fi
    if grep -qE "$DETECT_PATTERN" "$FILE" 2>/dev/null; then
      exit 1
    fi
    exit 0
    ;;

  *)
    echo "Usage: secret-redact.sh --scan <file> | --pipe | --check <file>" >&2
    exit 1
    ;;
esac
