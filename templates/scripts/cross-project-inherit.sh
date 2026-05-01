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
inherited = []
pending = []
for name, meta in patterns.items():
    try:
        n = int(meta.get("total_confirmations", 0))
    except Exception:
        n = 0
    promoted = meta.get("promoted_to")
    prom_s = promoted if promoted else "pending"
    ci = meta.get("confirmed_in") or []
    n_proj = len(ci) if isinstance(ci, list) else 0
    row = (name, n, prom_s, meta.get("impact", ""), n_proj)
    if n >= th:
        inherited.append(row)
    elif n >= 1:
        pending.append(row)

if inherited:
    print(f"  inherited knowledge (>={th} confirmations):")
    for name, n, prom_s, imp, n_proj in sorted(inherited, key=lambda x: -x[1]):
        hp = prom_s if str(prom_s).startswith("H") else f"promoted={prom_s}"
        print(f"    {hp} — {name} (confirmed in {n_proj} project(s), total_confirmations={n})")
        if imp:
            print(f"      impact: {imp}")
if pending:
    print("  pending (below inheritance threshold — still useful signal):")
    for name, n, prom_s, imp, n_proj in sorted(pending, key=lambda x: -x[1]):
        hp = prom_s if str(prom_s).startswith("H") else "pending"
        print(f"    {hp} — {name} (confirmed in {n_proj} project(s), total_confirmations={n})")
        if imp:
            print(f"      impact: {imp}")
if not inherited and not pending:
    print("  ok: no patterns in cross-project-evidence.json")
    raise SystemExit(0)
if inherited or pending:
    print("  ACTION: reflect promoted items in CLAUDE.md / learning-log when they apply to this repo")
PY

exit 0
