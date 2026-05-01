#!/usr/bin/env bash
# Append-only decision audit trail (.claude/decision-log.jsonl). Non-blocking; exit 0; LF-only.
# Generates sequential D-<YYYY-MM-DD>-<NNN> and echoes [OS-DECISION].
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

mkdir -p .claude
LOG="${DECISION_LOG_PATH:-${REPO_ROOT}/.claude/decision-log.jsonl}"
TMP="${REPO_ROOT}/.claude/session-state.tmp"

usage() {
  echo "usage: decision-audit.sh --type <type> --trigger <text> --policy <ref> --evidence <text> --decision <text> --confidence <HIGH|MEDIUM|LOW> --overridable <true|false>" >&2
  echo "  evidence: pipe-separated facts in one string (e.g. 'a|b')" >&2
  echo "  optional for scope_boundary: --scope-expansion-requested true|false" >&2
  exit 0
}

if ! command -v python3 >/dev/null 2>&1; then
  echo "[OS-DECISION] skip: python3 not available"
  exit 0
fi

TYPE=""
TRIGGER=""
POLICY=""
EVIDENCE=""
DECISION=""
CONFIDENCE=""
OVERRIDABLE=""
SCOPE_EXP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type) TYPE="${2:-}"; shift 2 ;;
    --trigger) TRIGGER="${2:-}"; shift 2 ;;
    --policy) POLICY="${2:-}"; shift 2 ;;
    --evidence) EVIDENCE="${2:-}"; shift 2 ;;
    --decision) DECISION="${2:-}"; shift 2 ;;
    --confidence) CONFIDENCE="${2:-}"; shift 2 ;;
    --overridable) OVERRIDABLE="${2:-}"; shift 2 ;;
    --scope-expansion-requested) SCOPE_EXP="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

VALID_TYPES='model_selection scope_boundary risk_acceptance invariant_override mode_escalation approval_gate'

if [[ -z "$TYPE" || -z "$TRIGGER" || -z "$POLICY" || -z "$DECISION" || -z "$CONFIDENCE" || -z "$OVERRIDABLE" ]]; then
  usage
fi

python3 - "$LOG" "$TMP" "$TYPE" "$TRIGGER" "$POLICY" "$EVIDENCE" "$DECISION" "$CONFIDENCE" "$OVERRIDABLE" "$SCOPE_EXP" "$VALID_TYPES" <<'PY'
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

log_path = Path(sys.argv[1])
tmp_path = Path(sys.argv[2])
typ = sys.argv[3]
trigger = sys.argv[4]
policy = sys.argv[5]
evidence_raw = sys.argv[6]
decision = sys.argv[7]
confidence = sys.argv[8]
overridable_s = sys.argv[9]
scope_exp = sys.argv[10]
valid_types = set(sys.argv[11].split())

err = []
if not typ or typ not in valid_types:
    err.append(f"invalid or missing --type (must be one of: {', '.join(sorted(valid_types))})")
if not trigger:
    err.append("missing --trigger")
if not policy:
    err.append("missing --policy")
if not decision:
    err.append("missing --decision")
if confidence.upper() not in ("HIGH", "MEDIUM", "LOW"):
    err.append("--confidence must be HIGH|MEDIUM|LOW")
ol = overridable_s.lower()
if ol not in ("true", "false"):
    err.append("--overridable must be true|false")
if err:
    print("[OS-DECISION] ERROR: " + "; ".join(err), file=sys.stderr)
    sys.exit(0)

evidence = [x.strip() for x in evidence_raw.split("|") if x.strip()] if evidence_raw else []

def session_id() -> str:
    if tmp_path.is_file():
        try:
            t = tmp_path.read_text(encoding="utf-8", errors="replace").strip()
            if t:
                return t[:200]
        except OSError:
            pass
    try:
        br = subprocess.run(
            ["git", "branch", "--show-current"],
            capture_output=True,
            text=True,
            check=False,
        ).stdout.strip() or "unknown"
    except Exception:
        br = "unknown"
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return f"{br}-{ts}"


def next_id_fixed() -> str:
    day = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    max_n = 0
    if log_path.is_file():
        try:
            for line in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                rid = str(obj.get("id", ""))
                m = re.match(rf"^D-{re.escape(day)}-(\d{{3}})$", rid)
                if m:
                    max_n = max(max_n, int(m.group(1)))
        except OSError:
            pass
    return f"D-{day}-{max_n + 1:03d}"

rid = next_id_fixed()  # sequential per UTC calendar day
ts = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
row = {
    "id": rid,
    "ts": ts,
    "session": session_id(),
    "type": typ,
    "trigger": trigger,
    "policy_applied": policy,
    "evidence": evidence,
    "decision": decision,
    "confidence": confidence.upper(),
    "overridable": ol == "true",
}
if typ == "scope_boundary":
    se = scope_exp.strip().lower()
    if se in ("true", "false"):
        row["scope_expansion_requested"] = se == "true"
    else:
        row["scope_expansion_requested"] = False
try:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("a", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")
except OSError as e:
    print(f"[OS-DECISION] ERROR: cannot write log: {e}", file=sys.stderr)
    sys.exit(0)

print(f"[OS-DECISION] Decision recorded: {rid} — {typ}: {decision}")
PY

exit 0
