#!/usr/bin/env bash
# Epistemic state — gate on ASSUMED/DISPUTED, decision quality from fact keys, assumption debt. H10: LF-only; exit 0.
set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

echo "[OS-EPISTEMIC]"

if ! command -v python3 >/dev/null 2>&1; then
  echo "  skip: python3 not available"
  exit 0
fi

export EPISTEMIC_STATE_PATH="${EPISTEMIC_STATE_PATH:-${REPO_ROOT}/.claude/epistemic-state.json}"

python3 - "$@" <<'PY'
import json
import os
import sys
from pathlib import Path

REPO = Path.cwd()
STATE = Path(os.environ.get("EPISTEMIC_STATE_PATH", str(REPO / ".claude" / "epistemic-state.json"))).expanduser().resolve()
REPORT = REPO / ".claude" / "epistemic-report.json"
LOG = REPO / ".claude" / "decision-log.jsonl"

VALID = {"KNOWN", "INFERRED", "ASSUMED", "UNKNOWN", "DISPUTED"}


def load_state():
    if not STATE.is_file():
        return None
    try:
        d = json.loads(STATE.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None
    facts = d.get("facts") if isinstance(d.get("facts"), dict) else {}
    unk = d.get("unknown_required") if isinstance(d.get("unknown_required"), list) else []
    return {"raw": d, "facts": facts, "unknown_required": unk}


def risk_rank(s: str) -> int:
    if not s:
        return 0
    u = s.upper()
    if "HIGH" in u:
        return 3
    if "MEDIUM" in u:
        return 2
    if "LOW" in u:
        return 1
    return 0


def match_fact_keys(facts: dict, token: str):
    token = (token or "").strip().lower()
    if not token:
        return []
    hits = []
    for k, meta in facts.items():
        if not isinstance(meta, dict):
            continue
        kid = (meta.get("id") or "").strip().lower()
        if token == k.lower() or token in k.lower() or (kid and token == kid):
            hits.append((k, meta))
    return hits


def score_facts(metas):
    """Returns (quality 0..1, counts by status)."""
    counts = {s: 0 for s in VALID}
    weights = []
    for m in metas:
        st = (m.get("status") or "UNKNOWN").upper()
        if st not in VALID:
            st = "UNKNOWN"
        counts[st] = counts.get(st, 0) + 1
        conf = m.get("confidence")
        try:
            c = float(conf) if conf is not None else 0.75
        except (TypeError, ValueError):
            c = 0.75
        c = max(0.0, min(1.0, c))
        if st == "KNOWN":
            weights.append(1.0)
        elif st == "INFERRED":
            weights.append(0.75 + 0.25 * c)
        elif st == "ASSUMED":
            weights.append(0.25 + 0.35 * c)
        elif st == "DISPUTED":
            weights.append(0.1 + 0.15 * c)
        else:
            weights.append(0.2 + 0.3 * c)
    if not weights:
        return 0.0, counts
    return sum(weights) / len(weights), counts


def read_decisions():
    rows = []
    if not LOG.is_file():
        return rows
    for line in LOG.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return rows


def main():
    args = sys.argv[1:]
    do_gate = "--gate" in args
    do_score = "--score-decision" in args
    do_score_all = "--score-all" in args
    do_debt = "--decision-debt" in args
    summary = "--summary" in args or (not do_gate and not do_score and not do_score_all and not do_debt)

    depends = os.environ.get("EPISTEMIC_PLAN_DEPENDS", "").strip()
    if "--depends" in args:
        i = args.index("--depends")
        depends = args[i + 1] if i + 1 < len(args) else ""

    dec_id = None
    if "--score-decision" in args:
        i = args.index("--score-decision")
        dec_id = args[i + 1] if i + 1 < len(args) else None

    st = load_state()
    if st is None:
        print(f"  skip: no epistemic state at {STATE.name} (bootstrap: epistemic-state.seed.json)")
        return

    facts = st["facts"]
    unknown_req = st["unknown_required"]

    assumed = [(k, v) for k, v in facts.items() if isinstance(v, dict) and (v.get("status") or "").upper() == "ASSUMED"]
    disputed = [(k, v) for k, v in facts.items() if isinstance(v, dict) and (v.get("status") or "").upper() == "DISPUTED"]
    inferred = [(k, v) for k, v in facts.items() if isinstance(v, dict) and (v.get("status") or "").upper() == "INFERRED"]

    report = {
        "state_file": str(STATE),
        "counts": {
            "KNOWN": sum(1 for _, v in facts.items() if isinstance(v, dict) and (v.get("status") or "").upper() == "KNOWN"),
            "INFERRED": len(inferred),
            "ASSUMED": len(assumed),
            "DISPUTED": len(disputed),
            "UNKNOWN": sum(
                1 for _, v in facts.items() if isinstance(v, dict) and (v.get("status") or "").upper() == "UNKNOWN"
            ),
        },
        "unknown_required": unknown_req,
    }

    if summary:
        if unknown_req:
            hi = [u for u in unknown_req if isinstance(u, dict) and (u.get("priority") or "").upper() == "HIGH"]
            print(f"  unknown_required: {len(unknown_req)} item(s) ({len(hi)} HIGH)")
            for u in unknown_req[:5]:
                if isinstance(u, dict):
                    print(f"    {u.get('id', '?')}: {u.get('question', '')[:100]}")
        if assumed:
            print(f"  assumption debt (ASSUMED facts): {len(assumed)}")
            for k, v in sorted(assumed, key=lambda x: -risk_rank(str(x[1].get("risk_if_wrong", ""))))[:8]:
                rk = v.get("risk_if_wrong", "?")
                cf = v.get("confidence", "?")
                print(f"    — ({cf}) [{rk}] {k[:90]}{'…' if len(k) > 90 else ''}")
            hr = sum(1 for _, v in assumed if risk_rank(str(v.get("risk_if_wrong"))) >= 3)
            if hr >= 2 or (hr >= 1 and len(assumed) >= 4):
                print("  WARN: assumption debt is HIGH — resolve ASSUMED/DISPUTED before Critical-mode work")
        elif disputed:
            print(f"  DISPUTED facts: {len(disputed)} — resolve contradictions before relying on them")
        else:
            print("  summary: no ASSUMED/DISPUTED facts registered (add facts to epistemic-state.json)")

    if do_gate and depends:
        print("  GATE: pre-implementation check")
        tokens = [t.strip() for t in depends.split(",") if t.strip()]
        blocked = []
        for t in tokens:
            for key, meta in match_fact_keys(facts, t):
                status = (meta.get("status") or "").upper()
                if status in ("ASSUMED", "DISPUTED"):
                    blocked.append((key, meta, status))
        if not blocked:
            print("    no ASSUMED/DISPUTED facts matched plan dependencies")
        for key, meta, status in blocked:
            cf = meta.get("confidence", "?")
            print(f"    plan depends on: {key[:100]}{'…' if len(key) > 100 else ''}")
            print(f"      status={status} confidence={cf}")
            vn = meta.get("verification_needed") or meta.get("resolution_needed")
            if vn:
                print(f"      required: {vn}")
            rk = meta.get("risk_if_wrong", "")
            if status == "ASSUMED" and risk_rank(str(rk)) >= 3:
                print("      Cannot proceed with HIGH-risk ASSUMED fact unverified (operational gate — resolve manually).")

    if do_score and dec_id:
        rows = read_decisions()
        row = next((r for r in rows if str(r.get("id")) == dec_id), None)
        if not row:
            print(f"  skip: decision {dec_id} not found in decision-log.jsonl")
        else:
            keys = row.get("epistemic_fact_keys") or []
            if not isinstance(keys, list) or not keys:
                print(f"  {dec_id}: no epistemic_fact_keys on record — add keys to score epistemic quality")
            else:
                metas = []
                for fk in keys:
                    if not isinstance(fk, str):
                        continue
                    hits = match_fact_keys(facts, fk)
                    if hits:
                        metas.append(hits[0][1])
                    else:
                        metas.append({"status": "UNKNOWN", "confidence": 0.5})
                q, cnt = score_facts(metas)
                print(f"  {dec_id} epistemic quality: {q:.2f}")
                print(f"    based on: {cnt.get('KNOWN',0)} KNOWN, {cnt.get('INFERRED',0)} INFERRED, {cnt.get('ASSUMED',0)} ASSUMED, {cnt.get('DISPUTED',0)} DISPUTED, {cnt.get('UNKNOWN',0)} UNKNOWN")
                if q < 0.55:
                    print("    WEAK decision — strengthen evidence or downgrade scope before merge")

    if do_score_all:
        rows = read_decisions()
        for row in rows[-30:]:
            keys = row.get("epistemic_fact_keys") or []
            if not isinstance(keys, list) or not keys:
                continue
            metas = []
            for fk in keys:
                if not isinstance(fk, str):
                    continue
                hits = match_fact_keys(facts, fk)
                metas.append(hits[0][1] if hits else {"status": "UNKNOWN", "confidence": 0.5})
            q, cnt = score_facts(metas)
            rid = row.get("id", "?")
            print(f"  {rid} quality={q:.2f} KNOWN={cnt.get('KNOWN')} INFERRED={cnt.get('INFERRED')} ASSUMED={cnt.get('ASSUMED')} DISPUTED={cnt.get('DISPUTED')}")

    if do_debt:
        rows = read_decisions()
        debt_lines = []
        for row in rows[-50:]:
            keys = row.get("epistemic_fact_keys") or []
            if not isinstance(keys, list):
                continue
            for fk in keys:
                if not isinstance(fk, str):
                    continue
                for key, meta in match_fact_keys(facts, fk):
                    if (meta.get("status") or "").upper() == "ASSUMED":
                        debt_lines.append((str(row.get("id", "?")), key, meta))
        if debt_lines:
            print(f"  assumption debt in recent decisions: {len(debt_lines)} fact link(s)")
            seen = set()
            for did, key, meta in debt_lines:
                sig = (did, key)
                if sig in seen:
                    continue
                seen.add(sig)
                print(f"    {did}: {key[:80]}{'…' if len(key)>80 else ''} — risk_if_wrong={meta.get('risk_if_wrong', '?')}")
        else:
            print("  no recent decisions reference ASSUMED facts (or no epistemic_fact_keys)")

    REPORT.parent.mkdir(parents=True, exist_ok=True)
    report["assumed_keys"] = [k for k, _ in assumed]
    REPORT.write_text(json.dumps(report, indent=2), encoding="utf-8")
    try:
        rel = REPORT.relative_to(REPO)
    except ValueError:
        rel = REPORT
    print(f"  report: {rel}")


if __name__ == "__main__":
    main()
PY

exit 0
