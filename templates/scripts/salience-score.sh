#!/usr/bin/env bash
# Context Salience Protocol — maps cognitive attention buckets to scores (0–100).
# Used to order injected context: higher score = earlier / stronger salience in the prompt.
# Non-blocking: always exit 0. LF-only line endings in repo.
set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT" || { echo "0"; exit 0; }

usage() {
  cat <<'USAGE' >&2
Usage:
  salience-score.sh --kind <name>     Print numeric score only (stdout).
  salience-score.sh --digest          Scan .claude/* state; print scored lines (descending).
  salience-score.sh --list-kinds      Print known kind names and scores.
  salience-score.sh --help

Kinds (fixed rubric): violated_invariant assumption_debt_high human_gate_pending
  policy_non_compliant critical_lease_active disputed_fact stale_invariant
  session_decision_low_confidence decision_affecting_module heuristic_surface historical_context
USAGE
}

score_for_kind() {
  case "$1" in
    violated_invariant) echo 95 ;;
    assumption_debt_high) echo 90 ;;
    human_gate_pending) echo 85 ;;
    policy_non_compliant) echo 82 ;;
    critical_lease_active) echo 80 ;;
    disputed_fact) echo 75 ;;
    stale_invariant) echo 60 ;;
    session_decision_low_confidence) echo 73 ;;
    decision_affecting_module) echo 50 ;;
    heuristic_surface) echo 40 ;;
    historical_context) echo 20 ;;
    *) echo 0 ;;
  esac
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "--list-kinds" ]]; then
  echo "violated_invariant=95"
  echo "assumption_debt_high=90"
  echo "human_gate_pending=85"
  echo "policy_non_compliant=82"
  echo "critical_lease_active=80"
  echo "disputed_fact=75"
  echo "stale_invariant=60"
  echo "session_decision_low_confidence=73"
  echo "decision_affecting_module=50"
  echo "heuristic_surface=40"
  echo "historical_context=20"
  exit 0
fi

if [[ "${1:-}" == "--kind" ]]; then
  k="${2:-}"
  score_for_kind "$k"
  exit 0
fi

# Positional shorthand: salience-score.sh violated_invariant
if [[ -n "${1:-}" && "${1:0:1}" != "-" ]]; then
  score_for_kind "$1"
  exit 0
fi

if [[ "${1:-}" != "--digest" ]]; then
  usage
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[OS-SALIENCE] digest skipped: python3 not available (use --list-kinds / --kind)" >&2
  exit 0
fi

python3 - "$REPO_ROOT" <<'PY'
"""Aggregate salience signals from existing OS artefacts; emit sorted score lines for Layer 0."""
from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(sys.argv[1])
claude = ROOT / ".claude"

# (score, category, one-line detail) — higher = more salient first
rows: list[tuple[int, str, str]] = []


def iso_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def parse_ts(s: str) -> datetime | None:
    if not s or not isinstance(s, str):
        return None
    try:
        if s.endswith("Z"):
            s = s[:-1] + "+00:00"
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError:
        return None


def load_json(p: Path) -> dict | list | None:
    if not p.is_file():
        return None
    try:
        return json.loads(p.read_text(encoding="utf-8", errors="replace"))
    except json.JSONDecodeError:
        return None


# 95 — VIOLATED invariants (from last invariant-report if present)
rep = load_json(claude / "invariant-report.json")
if isinstance(rep, dict) and int(rep.get("violated") or 0) > 0:
    det = rep.get("details") or []
    ids = [str(d.get("id")) for d in det if isinstance(d, dict) and str(d.get("status", "")).upper() == "VIOLATED"]
    tail = ", ".join(ids[:8]) if ids else "see invariant-engine --verify-all"
    rows.append((95, "violated_invariant", f"ACTIVE VIOLATIONS: {tail}"))

# 60 — STALE invariants (from invariants.json live state)
invf = load_json(claude / "invariants.json")
if isinstance(invf, dict):
    stale_ids = [
        str(i.get("id", "?"))
        for i in (invf.get("invariants") or [])
        if isinstance(i, dict) and str(i.get("status", "")).upper() == "STALE"
    ]
    if stale_ids:
        rows.append((60, "stale_invariant", f"STALE: {', '.join(stale_ids[:8])}"))

# 75 — DISPUTED facts; 90 — assumption debt (HIGH/CRITICAL ASSUMED + UNKNOWN weight)
ep = load_json(claude / "epistemic-state.json")
if isinstance(ep, dict):
    facts = ep.get("facts") or {}
    if isinstance(facts, dict):
        disputed = [k for k, m in facts.items() if isinstance(m, dict) and str(m.get("status", "")).upper() == "DISPUTED"]
        if disputed:
            rows.append((75, "disputed_fact", f"DISPUTED: {', '.join(disputed[:6])}"))
        debt_assumed = 0
        debt_unknown = 0
        for k, m in facts.items():
            if not isinstance(m, dict):
                continue
            st = str(m.get("status", "")).upper()
            rk = str(m.get("risk_if_wrong", "")).upper()
            if st == "ASSUMED" and rk in ("HIGH", "CRITICAL"):
                debt_assumed += 1
            if st == "UNKNOWN":
                debt_unknown += 1
        dscore = debt_assumed + debt_unknown * 2
        if dscore >= 4:
            rows.append((90, "assumption_debt_high", f"ASSUMPTION DEBT: score={dscore} (ASSUMED high/crit={debt_assumed}, UNKNOWN*2={debt_unknown*2})"))
        elif debt_assumed or debt_unknown:
            rows.append((88, "assumption_debt_high", f"assumption pressure: ASSUMED high/crit={debt_assumed}, UNKNOWN={debt_unknown}"))

# 80 — active WRITE leases (non-expired); 85 — approval_gate decisions recent
ag = load_json(claude / "agent-state.json")
if isinstance(ag, dict):
    now = datetime.now(timezone.utc)
    crit_pat = re.compile(r"auth|billing|secret|payment|migration|deploy", re.I)
    for L in ag.get("leases") or []:
        if not isinstance(L, dict):
            continue
        exp = parse_ts(str(L.get("expires", "")))
        if exp is not None and exp < now:
            continue
        typ = str(L.get("type", "")).upper()
        mod = str(L.get("module", ""))
        if typ == "WRITE":
            rows.append((80, "critical_lease_active", f"LEASE {L.get('id','?')} WRITE on {mod} (intent: {str(L.get('intent',''))[:80]})"))
        elif crit_pat.search(mod) and typ in ("READ", "WRITE", "EXCLUSIVE"):
            rows.append((78, "critical_lease_active", f"LEASE {L.get('id','?')} {typ} on critical path {mod}"))

idxp = claude / "session-index.json"
idx = load_json(idxp)
if isinstance(idx, dict):
    sessions = idx.get("sessions") or []
    if sessions and isinstance(sessions[-1], dict):
        decs = sessions[-1].get("decisions") or []
        weak_labels = frozenset({"AMBIGUOUS", "UNKNOWN", "ASSUMED", "DISPUTED"})
        weak_ids = []
        for d in decs:
            if not isinstance(d, dict):
                continue
            c = str(d.get("confidence", "")).strip().upper()
            if c in weak_labels:
                weak_ids.append(str(d.get("id", "?")))
        if weak_ids:
            rows.append(
                (
                    73,
                    "session_decision_low_confidence",
                    f"SESSION TABLE: review decisions {', '.join(weak_ids[:8])}",
                )
            )

logp = claude / "decision-log.jsonl"
if logp.is_file():
    try:
        tail_lines = logp.read_text(encoding="utf-8", errors="replace").splitlines()[-40:]
    except OSError:
        tail_lines = []
    for line in reversed(tail_lines):
        line = line.strip()
        if not line:
            continue
        try:
            r = json.loads(line)
        except json.JSONDecodeError:
            continue
        typ = str(r.get("type", "")).lower()
        dec = str(r.get("decision", "")).lower()
        if typ == "approval_gate" or ("human" in dec and "gate" in dec):
            rows.append((85, "human_gate_pending", f"OPEN GATE: {r.get('id','?')} — {str(r.get('decision',''))[:120]}"))
            break

# 82 — policy NON-COMPLIANT (informative; slightly below human_gate)
comp = load_json(claude / "compliance-report.json")
if isinstance(comp, dict):
    viol = comp.get("violations") or []
    if isinstance(viol, list) and viol:
        ids = [str(v.get("id", "?")) for v in viol if isinstance(v, dict)][:6]
        rows.append((82, "policy_non_compliant", f"POLICY NON-COMPLIANT decisions: {', '.join(ids)}"))

# De-duplicate identical (score, category, detail) while preserving max score per category message
seen: set[tuple[int, str, str]] = set()
uniq: list[tuple[int, str, str]] = []
for t in sorted(rows, key=lambda x: -x[0]):
    key = (t[0], t[1], t[2])
    if key in seen:
        continue
    seen.add(key)
    uniq.append(t)

print("[OS-SALIENCE] digest", iso_now())
print("# Lines: SCORE<TAB>CATEGORY<TAB>DETAIL — use top rows first in Layer 0")
for sc, cat, det in uniq[:24]:
    print(f"{sc}\t{cat}\t{det}")
if not uniq:
    print("20\thistorical_context\t(no elevated signals — default narrative/history layer suffices)")
PY

exit 0
