#!/usr/bin/env bash
# Append one governance decision record to .claude/decision-log.jsonl (append-only). H10: LF-only; exit 0.
set -euo pipefail

echo "[OS-DECISION-APPEND]"

if ! command -v python3 >/dev/null 2>&1; then
  echo "  skip: python3 not available"
  exit 0
fi

python3 - "$@" <<'PY'
import json
import sys
from pathlib import Path

REQUIRED = {"id", "ts", "type", "trigger", "policy_applied", "decision"}
LOG = Path(".claude/decision-log.jsonl")


def main():
    if len(sys.argv) > 1:
        src = Path(sys.argv[1]).read_text(encoding="utf-8").strip()
    else:
        src = sys.stdin.read().strip()
    if not src:
        print("  usage: decision-append.sh [path/to/one.json]   OR   echo '{...}' | decision-append.sh")
        return
    try:
        obj = json.loads(src)
    except json.JSONDecodeError as e:
        print(f"  invalid JSON: {e}")
        return
    if not isinstance(obj, dict):
        print("  entry must be a JSON object")
        return
    miss = REQUIRED - set(obj.keys())
    if miss:
        print(f"  missing required keys: {sorted(miss)}")
        return
    LOG.parent.mkdir(parents=True, exist_ok=True)
    line = json.dumps(obj, ensure_ascii=False, separators=(",", ":"))
    with LOG.open("a", encoding="utf-8") as f:
        f.write(line + "\n")
    print(f"  appended {obj.get('id')} → {LOG.as_posix()}")


if __name__ == "__main__":
    main()
PY

exit 0
