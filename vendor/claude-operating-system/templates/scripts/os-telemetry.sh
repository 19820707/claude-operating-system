#!/usr/bin/env bash
# OS telemetry — aggregates drift / ratchet / TS signals into .claude/os-metrics.json. H10: LF-only.
set -euo pipefail

echo "[OS-TELEMETRY]"

mkdir -p .claude

METRICS=".claude/os-metrics.json"
REPORT=0
for a in "$@"; do [ "$a" = "--report" ] && REPORT=1; done

python3 - "$METRICS" "$REPORT" <<'PY'
import json, os, re, subprocess, sys

path, report = sys.argv[1], int(sys.argv[2])

def load():
    if os.path.isfile(path):
        return json.load(open(path, "r", encoding="utf-8"))
    return {
        "updated": "",
        "sessions": 0,
        "phase_closes_git": 0,
        "drift_events": 0,
        "ratchet_violations": 0,
        "ts_regressions": 0,
        "last_h1": -1,
        "last_ts_count": -1,
        "score": "CLEAN",
    }

m = load()

if report:
    print(json.dumps(m, indent=2))
    sys.exit(0)

m["sessions"] = int(m.get("sessions", 0)) + 1

try:
    pc = subprocess.check_output(
        ["git", "log", "--oneline", "--", ".claude/session-state.md"],
        stderr=subprocess.DEVNULL,
        text=True,
    )
    m["phase_closes_git"] = len([l for l in pc.splitlines() if l.strip()])
except Exception:
    pass

# drift log last line
if os.path.isfile(".claude/drift.log"):
    lines = open(".claude/drift.log", "r", encoding="utf-8", errors="replace").read().splitlines()
    if lines:
        last = lines[-1]
        if re.search(r"(^|[,;])drift=1([,;]|$)", last):
            m["drift_events"] = int(m.get("drift_events", 0)) + 1

# ratchet h1
h1 = -1
if os.path.isfile(".local/heuristic-violations.json"):
    try:
        hv = json.load(open(".local/heuristic-violations.json", "r", encoding="utf-8"))
        h1 = int(hv.get("h1", -1))
    except Exception:
        h1 = -1
last_h1 = int(m.get("last_h1", -1))
if h1 >= 0 and last_h1 >= 0 and h1 > last_h1:
    m["ratchet_violations"] = int(m.get("ratchet_violations", 0)) + (h1 - last_h1)
m["last_h1"] = h1

# TS count vs baseline
base = -1
cur = -1
if os.path.isfile(".local/ts-error-budget.json"):
    try:
        tj = json.load(open(".local/ts-error-budget.json", "r", encoding="utf-8"))
        base = int(tj.get("baseline", -1))
    except Exception:
        base = -1
if base >= 0 and os.path.isfile("tsconfig.json") or os.path.isfile("tsconfig.base.json"):
    try:
        out = subprocess.run(
            ["npx", "tsc", "--noEmit"],
            capture_output=True,
            text=True,
        )
        blob = (out.stdout or "") + (out.stderr or "")
        cur = len(re.findall(r"error TS[0-9]+", blob))
    except Exception:
        cur = -1
if base >= 0 and cur >= 0 and cur > base:
    m["ts_regressions"] = int(m.get("ts_regressions", 0)) + 1
m["last_ts_count"] = cur

events = int(m.get("drift_events", 0)) + int(m.get("ratchet_violations", 0)) + int(m.get("ts_regressions", 0))
if events == 0:
    m["score"] = "CLEAN"
elif events <= 2:
    m["score"] = "WATCH"
else:
    m["score"] = "ALERT"

from datetime import datetime, timezone

m["updated"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

with open(path, "w", encoding="utf-8") as f:
    json.dump(m, f, indent=2)
    f.write("\n")

print(json.dumps(m, indent=2))
PY

exit 0
