#!/usr/bin/env bash
# Policy compliance audit over decision-log.jsonl. Non-blocking; exit 0; LF-only.
# Writes .claude/compliance-report.json; echoes [OS-AUDIT].
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

if ! command -v python3 >/dev/null 2>&1; then
  echo "  skip: python3 not available"
  exit 0
fi

LOG="${DECISION_LOG_PATH:-${REPO_ROOT}/.claude/decision-log.jsonl}"
OUT="${COMPLIANCE_REPORT_PATH:-${REPO_ROOT}/.claude/compliance-report.json}"

python3 - "$LOG" "$OUT" "$@" <<'PY'
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

LOG = Path(sys.argv[1])
OUT = Path(sys.argv[2])
args = sys.argv[3:]

session_filter = None
if "--session" in args:
    i = args.index("--session")
    session_filter = args[i + 1] if i + 1 < len(args) else None

CRITICAL = re.compile(
    r"auth|billing|migration|stripe|payment|webhook|secret|deploy|publish",
    re.I,
)


def is_sonnet(decision: str) -> bool:
    return "sonnet" in (decision or "").lower()


def check_row(r: dict) -> tuple[str, str]:
    """Returns (status, detail). status in COMPLIANT | NON-COMPLIANT | WEAK"""
    rid = str(r.get("id", "?"))
    typ = str(r.get("type", ""))
    trigger = str(r.get("trigger", ""))
    decision = str(r.get("decision", ""))

    if typ == "model_selection":
        if CRITICAL.search(trigger) and is_sonnet(decision):
            return "NON-COMPLIANT", "model=Sonnet on critical surface pattern"
        return "COMPLIANT", ""

    if typ == "scope_boundary":
        if r.get("scope_expansion_requested") is True:
            if "authoris" not in decision.lower():
                return "NON-COMPLIANT", "scope expanded without authorisation"
        return "COMPLIANT", ""

    if typ == "risk_acceptance":
        conf = str(r.get("confidence", "")).upper()
        ev = r.get("evidence") or []
        if not isinstance(ev, list):
            ev = []
        if conf == "LOW" and len(ev) < 2:
            return "WEAK", "low-confidence risk acceptance with insufficient evidence"
        return "COMPLIANT", ""

    return "COMPLIANT", ""


def main():
    print("[OS-AUDIT]")
    if not LOG.is_file():
        print("  skip: no decision-log.jsonl")
        rep = {
            "ts": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "session": session_filter,
            "total": 0,
            "compliant": 0,
            "violations": [],
            "rate": None,
        }
        OUT.parent.mkdir(parents=True, exist_ok=True)
        OUT.write_text(json.dumps(rep, indent=2), encoding="utf-8")
        return

    rows = []
    for line in LOG.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            continue

    if session_filter:
        rows = [r for r in rows if str(r.get("session", "")) == session_filter]

    checked_types = ("model_selection", "scope_boundary", "risk_acceptance")
    lines_out = []
    violations = []
    compliant = 0
    total = 0

    for r in rows:
        typ = str(r.get("type", ""))
        if typ not in checked_types:
            continue
        total += 1
        status, detail = check_row(r)
        rid = str(r.get("id", "?"))
        dec = str(r.get("decision", ""))
        trig = str(r.get("trigger", ""))[:80]
        if typ == "model_selection":
            label = f"{rid} model={dec.split()[0] if dec else '?'} for {trig}"
        else:
            label = f"{rid} {typ} trigger={trig}"
        if status == "COMPLIANT":
            compliant += 1
            lines_out.append(f"  {label} : COMPLIANT")
        elif status == "WEAK":
            violations.append({"id": rid, "type": typ, "reason": detail, "kind": "WEAK"})
            lines_out.append(f"  {label} : WEAK ({detail})")
        else:
            violations.append({"id": rid, "type": typ, "reason": detail, "kind": "NON-COMPLIANT"})
            lines_out.append(f"  {label} : NON-COMPLIANT ({detail})")

    rate = (compliant / total * 100.0) if total else None
    sess = session_filter or "(all sessions)"
    print(f"[OS-AUDIT] session: {sess}")
    for ln in lines_out[-40:]:
        print(ln)
    if total:
        print(f"  compliance rate: {rate:.1f}% ({compliant}/{total})")
        print(f"  violations: {len(violations)}")
        if rate is not None and rate < 85.0:
            print("  WARN: policy compliance degraded — review policies or discipline")
    else:
        print("  no model_selection / scope_boundary / risk_acceptance rows to audit")

    rep = {
        "ts": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "session": session_filter,
        "total": total,
        "compliant": compliant,
        "violations": violations,
        "rate": round(rate, 2) if rate is not None else None,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(rep, indent=2), encoding="utf-8")


if __name__ == "__main__":
    try:
        main()
    except OSError as e:
        print(f"  ERROR: {e}", file=sys.stderr)
PY

exit 0
