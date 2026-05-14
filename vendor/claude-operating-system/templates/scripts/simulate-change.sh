#!/usr/bin/env bash
# Forward simulation orchestrator — contract delta, blast, invariants, epistemic gaps. Exit 0; LF-only.
set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT" || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() {
  cat <<'U' >&2
Usage: simulate-change.sh --target <filepath> --change "<description>" [--type additive|breaking|refactor|unknown]
U
}

TARGET=""
CHANGE=""
CHG_TYPE="unknown"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    --change) CHANGE="${2:-}"; shift 2 ;;
    --type) CHG_TYPE="${2:-unknown}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[OS-SIMULATION] unknown arg: $1" >&2; usage; exit 0 ;;
  esac
done

if [[ -z "$TARGET" ]]; then
  usage
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[OS-SIMULATION] skip: python3 not available"
  exit 0
fi

export SIM_REPO="$REPO_ROOT"
export SIM_TARGET="${TARGET//\\//}"
export SIM_CHANGE="${CHANGE:-(unspecified)}"
export SIM_TYPE="${CHG_TYPE:-unknown}"
export SIM_SCRIPT_DIR="$SCRIPT_DIR"

CONTRACT_DIR="${REPO_ROOT}/.claude/contracts"
mkdir -p "$CONTRACT_DIR" 2>/dev/null || true

SLUG="$(python3 -c "
import re,sys
p=sys.argv[1].strip().replace('\\\\','/')
low=p.lower()
for suf in ('.ts','.tsx','.mts','.cts'):
    if low.endswith(suf):
        p=p[:-len(suf)];break
s=re.sub(r'[^a-zA-Z0-9/]+','-',p).replace('/','-').strip('-').lower()
print(re.sub(r'-+','-',s) or 'module')
" -- "$TARGET")"

BASE_JSON="${CONTRACT_DIR}/${SLUG}.json"
STEP1_OUT=""
if [[ -f "$BASE_JSON" ]]; then
  STEP1_OUT="$(bash "${SCRIPT_DIR}/contract-delta.sh" --compare "$TARGET" --baseline "$BASE_JSON" 2>&1 || true)"
else
  STEP1_OUT="$(bash "${SCRIPT_DIR}/contract-delta.sh" --snapshot "$TARGET" 2>&1 || true)"
  STEP1_OUT="${STEP1_OUT}"$'\n'"[OS-SIMULATION] No baseline contract — first simulation. Snapshot created for future comparisons."
fi

export SIM_STEP1_TEXT="$STEP1_OUT"

python3 - <<'PY'
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(os.environ["SIM_REPO"])
target = os.environ["SIM_TARGET"].replace("\\", "/")
change = os.environ["SIM_CHANGE"]
chg_type = os.environ.get("SIM_TYPE", "unknown")
step1 = os.environ.get("SIM_STEP1_TEXT", "")

slug = target
low = target.lower()
for suf in (".ts", ".tsx", ".mts", ".cts"):
    if low.endswith(suf):
        slug = target[: -len(suf)]
        break
slug = re.sub(r"[^a-zA-Z0-9/]+", "-", slug).replace("/", "-").strip("-").lower()
slug = re.sub(r"-+", "-", slug) or "module"
base_json = ROOT / ".claude" / "contracts" / f"{slug}.json"
meta_cmp = ROOT / ".claude" / "contracts" / ".last-compare.json"

contract_delta = {"worst": "UNKNOWN", "deltas": [], "step1_log": step1[:4000]}
if "No baseline contract" in step1:
    contract_delta = {"worst": "NEUTRAL", "deltas": [], "note": "first snapshot only"}
elif meta_cmp.is_file():
    try:
        contract_delta = json.loads(meta_cmp.read_text(encoding="utf-8", errors="replace"))
    except json.JSONDecodeError:
        pass

basename = Path(target).name
blast = {
    "direct_count": 0,
    "transitive_count": 0,
    "direct_files": [],
    "transitive_files": [],
    "test_count": 0,
    "test_files": [],
    "method": "knowledge-graph",
}

kg_path = ROOT / ".claude" / "knowledge-graph.json"
if kg_path.is_file():
    try:
        kg = json.loads(kg_path.read_text(encoding="utf-8", errors="replace"))
    except json.JSONDecodeError:
        kg = {"edges": []}
    edges = kg.get("edges") or []
    direct = sorted({e.get("from") for e in edges if e.get("to") == target and isinstance(e.get("from"), str)})
    blast["direct_files"] = direct
    blast["direct_count"] = len(direct)
    rev = {}
    for e in edges:
        if not isinstance(e, dict):
            continue
        f, t = e.get("from"), e.get("to")
        if isinstance(f, str) and isinstance(t, str):
            rev.setdefault(t, []).append(f)
    seen = {target}
    frontier = list(direct)
    depth = {m: 1 for m in direct}
    while frontier:
        n = frontier.pop()
        for imp in rev.get(n, []):
            if imp in seen:
                continue
            d = depth.get(n, 1) + 1
            if d > 2:
                continue
            seen.add(imp)
            depth[imp] = d
            frontier.append(imp)
    blast["transitive_files"] = sorted(x for x in seen if x != target)
    blast["transitive_count"] = len(blast["transitive_files"])
    tre = re.compile(r"\.(test|spec)\.(tsx?|mts|cts)$|__tests__/")
    tests = [f for f in blast["transitive_files"] if tre.search(f)]
    stem = Path(target).stem
    name = Path(target).name
    grep_tests = set(tests)
    for gl in (
        "**/*.test.ts",
        "**/*.test.tsx",
        "**/*.spec.ts",
        "**/*.spec.tsx",
        "**/*.test.mts",
        "**/*.spec.mts",
    ):
        for p in ROOT.glob(gl):
            rs = str(p.relative_to(ROOT)).replace("\\", "/")
            if any(
                x in rs
                for x in ("node_modules", "dist", ".claude", "build", ".git", "coverage")
            ):
                continue
            try:
                tx = p.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            if stem in tx or name in tx:
                grep_tests.add(rs)
    blast["test_files"] = sorted(grep_tests)
    blast["test_count"] = len(grep_tests)
    blast["test_match"] = "closure+grep-basename"
else:
    blast["method"] = "grep"
    try:
        cp = subprocess.run(
            ["git", "-C", str(ROOT), "ls-files", "*.ts", "*.tsx"],
            capture_output=True,
            text=True,
            check=False,
        )
        hits = []
        needle = basename.replace(".ts", "").replace(".tsx", "")
        for rel in cp.stdout.splitlines():
            rel = rel.strip().replace("\\", "/")
            if not rel or "node_modules" in rel:
                continue
            try:
                txt = (ROOT / rel).read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            if needle and needle in txt:
                hits.append(rel)
        blast["transitive_files"] = sorted(set(hits))[:80]
        blast["transitive_count"] = len(blast["transitive_files"])
        blast["direct_count"] = blast["transitive_count"]
        blast["direct_files"] = blast["transitive_files"][:20]
        tre = re.compile(r"\.(test|spec)\.(tsx?|mts|cts)$|__tests__/")
        blast["test_files"] = [f for f in hits if tre.search(f)]
        blast["test_count"] = len(blast["test_files"])
    except Exception as e:
        blast["error"] = str(e)

inv_path = ROOT / ".claude" / "invariants.json"
at_risk = []
if inv_path.is_file():
    try:
        data = json.loads(inv_path.read_text(encoding="utf-8", errors="replace"))
    except json.JSONDecodeError:
        data = {}
    invs = data.get("invariants") or []
    tdir = str(Path(target).parent.as_posix()).lower()
    tlow = target.lower()
    chg_l = change.lower()
    for inv in invs:
        if not isinstance(inv, dict):
            continue
        if str(inv.get("status", "")).upper() == "OBSOLETE":
            continue
        chk = inv.get("check") or {}
        sc = str(chk.get("scope", "") or "").lower().replace("\\", "/")
        pat = str(chk.get("pattern", "") or "")
        level = None
        reason = ""
        if sc and (tlow == sc or tlow.startswith(sc.rstrip("/") + "/")):
            level, reason = "AT_RISK", "module in scope"
        elif pat:
            try:
                if re.search(pat, change, re.I) or re.search(pat, target, re.I):
                    level, reason = "MONITOR", "pattern may interact with target/change"
            except re.error:
                pass
        if level:
            at_risk.append(
                {
                    "id": inv.get("id"),
                    "name": inv.get("name", ""),
                    "level": level,
                    "reason": reason,
                }
            )
        elif chk.get("type") == "dependency_absent" and (
            tlow.startswith("client/") or tlow.startswith("server/")
        ):
            at_risk.append(
                {
                    "id": inv.get("id"),
                    "name": inv.get("name", ""),
                    "level": "MONITOR",
                    "reason": "client/server surface",
                }
            )
    seen_iid = set()
    ded_inv = []
    for x in at_risk:
        iid = x.get("id")
        if not iid or iid in seen_iid:
            continue
        seen_iid.add(iid)
        ded_inv.append(x)
    at_risk = ded_inv

epi_gaps = []
epi_path = ROOT / ".claude" / "epistemic-state.json"
if epi_path.is_file():
    try:
        ep = json.loads(epi_path.read_text(encoding="utf-8", errors="replace"))
    except json.JSONDecodeError:
        ep = {}
    facts = ep.get("facts") or {}
    adj = Path(target).parent.as_posix()
    if isinstance(facts, dict):
        for fk, meta in facts.items():
            if not isinstance(meta, dict):
                continue
            st = str(meta.get("status", "")).upper()
            if st not in ("ASSUMED", "UNKNOWN"):
                continue
            stt = str(meta.get("statement", ""))
            if target.lower() in stt.lower() or adj.lower() in stt.lower():
                epi_gaps.append(
                    {
                        "slug": fk,
                        "status": st,
                        "confidence": meta.get("confidence"),
                        "risk": meta.get("risk_if_wrong"),
                        "statement": stt[:200],
                    }
                )

worst = str(contract_delta.get("worst", "UNKNOWN"))
trans_n = int(blast.get("transitive_count") or 0)
rec = "SIMULATION CLEAR: proceed with standard discipline"
if worst == "BREAKING":
    rec = "SPLIT RECOMMENDED: make change additive first, breaking in separate phase"
elif trans_n > 10:
    rec = "HIGH BLAST RADIUS: consider interface abstraction to reduce coupling"
if len([x for x in at_risk if x.get("level") == "AT_RISK"]) > 2:
    rec = "VERIFY INVARIANTS: run /verify-invariants before proceeding"
if any(
    g.get("risk") in ("HIGH", "CRITICAL") and g.get("status") == "ASSUMED" for g in epi_gaps
):
    rec = "RESOLVE ASSUMPTIONS: run /epistemic-review before proceeding"

report = {
    "target": target,
    "change": change,
    "change_type": chg_type,
    "contract_delta": contract_delta,
    "blast_radius": blast,
    "invariants_at_risk": at_risk,
    "epistemic_gaps": epi_gaps,
    "recommendation": rec,
}
outp = ROOT / ".claude" / "simulation-report.json"
outp.parent.mkdir(parents=True, exist_ok=True)
outp.write_text(json.dumps(report, indent=2), encoding="utf-8", newline="\n")

print(f"[OS-SIMULATION] target: {target}")
print("")
print("CONTRACT DELTA:")
for ln in step1.splitlines()[:40]:
    print(ln)
print("")
print("BLAST RADIUS:")
print(f"  direct:     {blast['direct_count']} files ({', '.join(blast['direct_files'][:8])}{'...' if len(blast.get('direct_files') or [])>8 else ''})")
print(f"  transitive: {blast['transitive_count']} files (depth ≤ 2 when KG used)")
print(f"  tests:      {blast['test_count']} test-like files")
if blast.get("method") == "grep":
    print("  note: knowledge-graph.json not available — grep/list heuristic (less precise)")
print("")
print("INVARIANTS AT RISK:")
if not at_risk:
    print("  no invariants at risk for this change (or no match)")
else:
    for x in at_risk:
        print(f"  {x.get('id')} {x.get('name')}: {x.get('level')} ({x.get('reason')})")
print("")
if epi_gaps:
    print("EPISTEMIC GAPS:")
    for g in epi_gaps:
        st = g.get("status")
        if st == "ASSUMED":
            tail = " — verify before proceeding"
        elif st == "UNKNOWN":
            tail = " — blocking this change"
        else:
            tail = ""
        print(
            f"  {st}: {g.get('slug')} (confidence: {g.get('confidence')}, risk: {g.get('risk')}) — {g.get('statement','')[:120]}{tail}"
        )
    print("")
print("RECOMMENDATION:")
print(f"  {rec}")
PY

exit 0
