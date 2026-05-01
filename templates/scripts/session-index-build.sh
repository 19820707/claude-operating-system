#!/usr/bin/env bash
# Semantic Session Continuity — merges optional YAML front-matter from session-state into session-index.json.
# Non-blocking; exit 0. H10: LF-only.
set -euo pipefail

echo "[OS-SESSION-INDEX]"

if ! command -v python3 >/dev/null 2>&1; then
  echo "  skip: python3 not available"
  exit 0
fi

mkdir -p .claude

python3 - <<'PY'
import json, re
from datetime import datetime, timezone
from pathlib import Path

state = Path(".claude/session-state.md")
out = Path(".claude/session-index.json")
if not state.is_file():
    print("  skip: no .claude/session-state.md")
    raise SystemExit(0)

raw = state.read_text(encoding="utf-8", errors="replace")
if not raw.lstrip("\ufeff").startswith("---"):
    print(
        "  skip: session-state.md has no YAML front matter (opt-in). "
        "Add ---\\n...\\n--- block at top to enable index."
    )
    raise SystemExit(0)

end = raw.find("\n---", 3)
if end == -1:
    print("  skip: malformed YAML front matter (missing closing ---)")
    raise SystemExit(0)

block = raw[3:end]
body = raw[end + 4 :]
fm: dict = {}
for line in block.splitlines():
    line = line.strip()
    if not line or line.startswith("#") or ":" not in line:
        continue
    k, v = line.split(":", 1)
    k, v = k.strip(), v.strip()
    if k in ("modules_touched", "risks_opened", "risks_closed", "heuristics_applied"):
        if v.startswith("[") and v.endswith("]"):
            inner = v[1:-1].strip()
            fm[k] = [x.strip().strip("'\"") for x in inner.split(",") if x.strip()]
        else:
            fm[k] = [v] if v else []
    elif k == "decisions":
        fm[k] = v
    else:
        fm[k] = v

branch = ""
head = ""
for line in body.splitlines():
    m = re.match(r"^\|\s*Branch\s*\|\s*`?([^`|]+)`?\s*\|", line, re.I)
    if m:
        branch = m.group(1).strip()
    m = re.match(r"^\|\s*HEAD\s*\|\s*`?([^`|]+)`?\s*\|", line, re.I)
    if m:
        head = m.group(1).strip().split()[0]

sid = fm.get("session_id") or fm.get("id")
if not sid:
    short = head[:7] if head else "unknown"
    sid = f"{datetime.now(timezone.utc).strftime('%Y-%m-%d')}--{short}"

entry = {
    "id": sid,
    "phase": fm.get("phase", ""),
    "modules_touched": fm.get("modules_touched", []),
    "decisions": fm.get("decisions", []),
    "risks_opened": fm.get("risks_opened", []),
    "risks_closed": fm.get("risks_closed", []),
    "heuristics_applied": fm.get("heuristics_applied", []),
    "branch": branch,
    "head": head,
    "indexed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}

idx = {"schemaVersion": 1, "sessions": [], "decisions_by_module": {}, "open_risks": []}
if out.is_file():
    try:
        idx = json.loads(out.read_text(encoding="utf-8"))
    except Exception:
        pass

sessions = idx.get("sessions", [])
if sid in [s.get("id") for s in sessions]:
    sessions = [s for s in sessions if s.get("id") != sid]
sessions.append(entry)
idx["sessions"] = sessions[-200:]
idx["updated"] = entry["indexed_at"]

dbm = idx.get("decisions_by_module") or {}
for mod in entry.get("modules_touched") or []:
    dbm.setdefault(mod, []).append({"session": sid, "head": head})
idx["decisions_by_module"] = dbm
idx["open_risks"] = entry.get("risks_opened", [])

out.write_text(json.dumps(idx, indent=2), encoding="utf-8")
print(f"  ok: merged session '{sid}' into {out} ({len(idx['sessions'])} total)")
PY

exit 0
