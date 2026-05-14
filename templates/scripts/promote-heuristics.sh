#!/usr/bin/env bash
# Promote learning-log YAML blocks to operational heuristics (human-curated YAML).
# For auto-detected patterns see autonomous-learning-loop.sh → learning-loop-report.json → learning-log front-matter.
# H10: LF-only.
set -euo pipefail

echo "[OS-HEURISTIC-PROMOTE]"

LOG=".claude/learning-log.md"
if [ ! -f "$LOG" ]; then
  echo "  skip: no ${LOG}"
  exit 0
fi

TARGET=".claude/heuristics/operational.md"
mkdir -p .claude/heuristics 2>/dev/null || true
if [ ! -w ".claude/heuristics" ] 2>/dev/null; then
  mkdir -p heuristics 2>/dev/null || true
  TARGET="heuristics/operational.md"
fi

export HEURISTIC_TARGET="$TARGET"
python3 - "$@" <<'PY'
import os, re, sys
from datetime import datetime, timezone

log_path = ".claude/learning-log.md"
target = os.environ.get("HEURISTIC_TARGET", ".claude/heuristics/operational.md")
promote = "--promote" in sys.argv

text = open(log_path, "r", encoding="utf-8", errors="replace").read()
blocks = []
cur = []
in_fm = False
for line in text.splitlines():
    if line.strip() == "---":
        if in_fm:
            blocks.append("\n".join(cur))
            cur = []
            in_fm = False
        else:
            in_fm = True
        continue
    if in_fm:
        cur.append(line)


def field(block, name):
    m = re.search(rf"^{name}:\s*(.*)$", block, re.M | re.I)
    return m.group(1).strip() if m else ""


candidates = {}
for block in blocks:
    pat = field(block, "pattern")
    if not pat:
        continue
    ev = field(block, "evidence")
    heur = field(block, "heuristic") or "H?"
    conf = field(block, "confirmed")
    try:
        c = int(conf) if conf else 1
    except ValueError:
        c = 1
    agg = candidates.setdefault(pat, {"evidence": ev, "heuristic": heur, "count": 0})
    agg["count"] += c
    if ev and not agg.get("evidence"):
        agg["evidence"] = ev

for pat, data in sorted(candidates.items(), key=lambda x: -x[1]["count"]):
    if data["count"] >= 2:
        print(f"CANDIDATE\t{pat}\tconfirmed={data['count']}\t{data['heuristic']}\t{data.get('evidence','')}")

if not promote:
    sys.exit(0)

os.makedirs(os.path.dirname(target) or ".", exist_ok=True)
existing = ""
if os.path.isfile(target):
    existing = open(target, "r", encoding="utf-8", errors="replace").read()

ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
appends = []
for pat, data in sorted(candidates.items(), key=lambda x: -x[1]["count"]):
    if data["count"] < 2:
        continue
    if pat in existing:
        continue
    hid = data["heuristic"] or "H?"
    appends.append(
        f"\n### {hid} — {pat}\n"
        f"**Evidence:** {data.get('evidence','')}\n"
        f"**Confirmed:** {data['count']}x\n"
        f"**Promoted:** {ts}\n"
        f"**Rule:** [fill in]\n"
        f"**Apply:** [fill in]\n"
    )

if appends:
    with open(target, "a", encoding="utf-8") as f:
        f.write("\n".join(appends))
    print(f"PROMOTED -> {target} ({len(appends)} entries)")
else:
    print("PROMOTED -> (nothing new)")
PY

exit 0
