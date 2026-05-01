#!/usr/bin/env bash
# Cross-Project Intelligence — prints patterns from cross-project-evidence.json (confirmations >= threshold).
# Non-blocking; exit 0. H10: LF-only.
set -euo pipefail

echo "[OS-CROSS-PROJECT]"

THRESH=2
for a in "$@"; do
  case "$a" in
    --threshold=*) THRESH="${a#--threshold=}" ;;
  esac
done

JSON=".claude/heuristics/cross-project-evidence.json"
if [ ! -f "$JSON" ]; then
  echo "  skip: no ${JSON}"
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "  skip: python3 not available"
  exit 0
fi

python3 - "$JSON" "$THRESH" <<'PY'
import json, sys
path, th = sys.argv[1], int(sys.argv[2])
try:
    data = json.load(open(path, "r", encoding="utf-8"))
except Exception as e:
    print(f"  skip: invalid json ({e})")
    raise SystemExit(0)
patterns = data.get("patterns") or {}
out = []
for name, meta in patterns.items():
    try:
        n = int(meta.get("total_confirmations", 0))
    except Exception:
        n = 0
    if n >= th:
        promoted = meta.get("promoted_to") or "pending"
        out.append((name, n, promoted, meta.get("impact", "")))
if not out:
    print(f"  ok: no patterns >= {th} confirmations")
    raise SystemExit(0)
print(f"  inherited knowledge candidates (>={th} confirmations):")
for name, n, prom, imp in sorted(out, key=lambda x: -x[1]):
    print(f"    - {name}: confirmations={n} promoted={prom}")
    if imp:
        print(f"      impact: {imp}")
print("  ACTION: ensure these appear in learning-log / operational heuristics when relevant to this repo")
PY

exit 0
