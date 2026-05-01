#!/usr/bin/env bash
# Epistemic registry: facts, unknowns, gates, scoring. Non-blocking; exit 0; LF-only.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

if ! command -v python3 >/dev/null 2>&1; then
  echo "[OS-EPISTEMIC] skip: python3 not available"
  exit 0
fi

export EPI_REPO="$REPO_ROOT"
ARGS_JSON="$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' -- "$@")"
export ARGS_JSON

python3 - <<'PY'
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(os.environ["EPI_REPO"])
argv = json.loads(os.environ.get("ARGS_JSON", "[]"))
STATE = ROOT / ".claude" / "epistemic-state.json"
REPORT = ROOT / ".claude" / "epistemic-report.json"


def load():
    if not STATE.is_file():
        return {"facts": {}, "unknown_required": []}
    try:
        return json.loads(STATE.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {"facts": {}, "unknown_required": []}


def save(d):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(d, indent=2), encoding="utf-8")


def main():
    if not argv:
        print("[OS-EPISTEMIC] usage: --add ... | --gate ... | --score ... | --debt | --verify-assumed | --report")
        return
    mode = argv[0]
    d = load()
    facts = d.setdefault("facts", {})
    unk = d.setdefault("unknown_required", [])

    if mode == "--add":
        # --add --fact slug --statement t --status S --evidence e --confidence 0.5 --risk LOW
        try:
            slug = argv[argv.index("--fact") + 1]
            stmt = argv[argv.index("--statement") + 1]
            st = argv[argv.index("--status") + 1].upper()
            ev = argv[argv.index("--evidence") + 1]
            conf = float(argv[argv.index("--confidence") + 1])
            risk = argv[argv.index("--risk") + 1].upper()
        except (ValueError, IndexError):
            print("[OS-EPISTEMIC] ERROR: --add --fact <slug> --statement <t> --status <S> --evidence <e> --confidence <n> --risk <R>")
            return
        vc = None
        if "--verification-command" in argv:
            vc = argv[argv.index("--verification-command") + 1]
        facts[slug] = {
            "statement": stmt,
            "status": st,
            "evidence": ev,
            "confidence": conf,
            "risk_if_wrong": risk,
            "last_verified": None,
            "verification_command": vc,
            "blocking_decisions": facts.get(slug, {}).get("blocking_decisions") or [],
        }
        save(d)
        print(f"[OS-EPISTEMIC] recorded: {slug} ({st}, confidence: {conf})")
        return

    if mode == "--gate":
        try:
            did = argv[argv.index("--decision") + 1]
            deps = argv[argv.index("--depends-on") + 1].split(",")
        except (ValueError, IndexError):
            print("[OS-EPISTEMIC] ERROR: --gate --decision <D-NNN> --depends-on <slug,...>")
            return
        failed = False
        for raw in deps:
            slug = raw.strip()
            if not slug:
                continue
            f = facts.get(slug)
            if not f:
                print(f"[OS-EPISTEMIC] GATE FAILED: unknown fact slug {slug}")
                failed = True
                continue
            st = str(f.get("status", "")).upper()
            rk = str(f.get("risk_if_wrong", "")).upper()
            if st == "ASSUMED" and rk in ("HIGH", "CRITICAL"):
                print(f"[OS-EPISTEMIC] GATE: {slug} is ASSUMED with {rk} risk — verify before proceeding")
                vc = f.get("verification_command")
                if vc:
                    print(f"  verification: {vc}")
                failed = True
            if st == "DISPUTED":
                print(f"[OS-EPISTEMIC] GATE FAILED: disputed fact {slug} — resolve contradiction first")
                failed = True
            if st == "UNKNOWN":
                print(f"[OS-EPISTEMIC] GATE FAILED: unknown required fact {slug} — must be established")
                failed = True
        if not failed:
            print(f"[OS-EPISTEMIC] GATE PASSED: epistemic base is solid for {did}")
        return

    if mode == "--score":
        try:
            did = argv[argv.index("--decision") + 1]
        except (ValueError, IndexError):
            print("[OS-EPISTEMIC] ERROR: --score --decision <D-NNN>")
            return
        linked = []
        for slug, meta in facts.items():
            b = meta.get("blocking_decisions") or []
            if did in [str(x) for x in b]:
                linked.append((slug, meta))
        if not linked:
            for slug, meta in facts.items():
                linked.append((slug, meta))
        confs = []
        assumed_pen = 0
        disp_pen = 0
        unk_pen = 0
        buckets = {"KNOWN": 0, "INFERRED": 0, "ASSUMED": 0, "DISPUTED": 0, "UNKNOWN": 0}
        for slug, meta in linked:
            st = str(meta.get("status", "UNKNOWN")).upper()
            buckets[st] = buckets.get(st, 0) + 1
            c = float(meta.get("confidence") or 0.5)
            confs.append(c)
            rk = str(meta.get("risk_if_wrong", "")).upper()
            if st == "ASSUMED" and rk in ("HIGH", "CRITICAL"):
                assumed_pen += 1
            if st == "DISPUTED":
                disp_pen += 1
            if st == "UNKNOWN":
                unk_pen += 1
        base = sum(confs) / len(confs) if confs else 0.0
        score = base - 0.2 * assumed_pen - 0.3 * disp_pen - 0.4 * unk_pen
        score = max(0.0, min(1.0, score))
        print(f"[OS-EPISTEMIC] {did} epistemic quality: {score:.2f}")
        print(f"  {buckets['KNOWN']} KNOWN, {buckets['INFERRED']} INFERRED, {buckets['ASSUMED']} ASSUMED, {buckets['DISPUTED']} DISPUTED, {buckets['UNKNOWN']} UNKNOWN")
        if score >= 0.65:
            print("  solid decision — evidence base is strong")
        else:
            print("  weak epistemic base — resolve ASSUMED/DISPUTED/UNKNOWN before merge")
        REPORT.parent.mkdir(parents=True, exist_ok=True)
        REPORT.write_text(json.dumps({"decision": did, "score": score, "buckets": buckets}, indent=2), encoding="utf-8")
        return

    if mode == "--debt":
        debt = []
        for slug, meta in facts.items():
            st = str(meta.get("status", "")).upper()
            rk = str(meta.get("risk_if_wrong", "")).upper()
            if st == "ASSUMED" and rk in ("HIGH", "CRITICAL"):
                debt.append(("ASSUMED", slug, meta))
        for u in unk:
            debt.append(("UNKNOWN", u.get("id", "?"), u))
        score = sum(1 for t, _, _ in debt if t == "ASSUMED") + sum(2 for t, _, _ in debt if t == "UNKNOWN")
        print(f"[OS-EPISTEMIC] assumption debt: {score}")
        for t, k, m in debt[:12]:
            if t == "ASSUMED":
                print(f"  ASSUMED {k}: {m.get('statement', '')[:80]}")
            else:
                print(f"  UNKNOWN {k}: {m.get('question', '')[:80]}")
        if score >= 4:
            print("  WARN: assumption debt is HIGH — resolve before Critical mode work")
        return

    if mode == "--verify-assumed":
        for slug, meta in facts.items():
            if str(meta.get("status", "")).upper() != "ASSUMED":
                continue
            cmd = meta.get("verification_command")
            if not cmd:
                continue
            try:
                cp = subprocess.run(
                    cmd,
                    shell=True,
                    cwd=str(ROOT),
                    capture_output=True,
                    text=True,
                    timeout=60,
                    check=False,
                )
                out = (cp.stdout or "") + (cp.stderr or "")
                if out.strip():
                    print(f"[OS-EPISTEMIC] VERIFIABLE: {slug} — command produced output; review to promote to KNOWN")
            except Exception as e:
                print(f"[OS-EPISTEMIC] {slug}: verify command failed: {e}")
        return

    if mode == "--report":
        print("[OS-EPISTEMIC] full state")
        for slug, meta in facts.items():
            print(f"  {slug}: {meta.get('status')} conf={meta.get('confidence')} — {str(meta.get('statement', ''))[:100]}")
        for u in unk:
            print(f"  {u.get('id')}: {u.get('question', '')[:100]} [{u.get('priority')}]")
        return

    print(f"[OS-EPISTEMIC] unknown mode {mode}")


try:
    main()
except Exception as e:
    print(f"[OS-EPISTEMIC] ERROR: {e}", file=sys.stderr)
PY

exit 0
