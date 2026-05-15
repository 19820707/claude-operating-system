#!/usr/bin/env bash
# Multi-session coordination: leases + shared decisions in .claude/agent-state.json. exit 0; LF-only.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

if ! command -v python3 >/dev/null 2>&1; then
  echo "[OS-COORDINATOR] skip: python3 not available"
  exit 0
fi

export AGENT_COORD_REPO="$REPO_ROOT"
ARGS_JSON="$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' -- "$@")"
export ARGS_JSON

python3 - <<'PY'
import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(os.environ["AGENT_COORD_REPO"])
argv = json.loads(os.environ.get("ARGS_JSON", "[]"))
STATE = ROOT / ".claude" / "agent-state.json"


def now():
    return datetime.now(timezone.utc)


def now_iso():
    return now().isoformat().replace("+00:00", "Z")


def session_id():
    try:
        import subprocess
        br = subprocess.run(
            ["git", "-C", str(ROOT), "branch", "--show-current"],
            capture_output=True,
            text=True,
            check=False,
        ).stdout.strip() or "unknown"
    except Exception:
        br = "unknown"
    return f"{br}-{now().strftime('%H')}"


def load():
    if not STATE.is_file():
        return {"leases": [], "shared_decisions": []}
    try:
        d = json.loads(STATE.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {"leases": [], "shared_decisions": []}
    d.setdefault("leases", [])
    d.setdefault("shared_decisions", [])
    return d


def save(d):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(d, indent=2), encoding="utf-8")


def next_lease_id(leases):
    n = 0
    for L in leases:
        m = re.match(r"^LEASE-(\d+)$", str(L.get("id", "")))
        if m:
            n = max(n, int(m.group(1)))
    return f"LEASE-{n + 1:03d}"


def next_sd_id(sds):
    n = 0
    for s in sds:
        m = re.match(r"^SD-(\d+)$", str(s.get("id", "")))
        if m:
            n = max(n, int(m.group(1)))
    return f"SD-{n + 1:03d}"


def active_leases(leases):
    t = now()
    out = []
    for L in leases:
        exp = L.get("expires")
        if not exp:
            out.append(L)
            continue
        try:
            et = datetime.fromisoformat(str(exp).replace("Z", "+00:00"))
            if et.tzinfo is None:
                et = et.replace(tzinfo=timezone.utc)
            if et > t:
                out.append(L)
        except ValueError:
            out.append(L)
    return out


def glob_overlap(a: str, b: str) -> bool:
    if not a or not b:
        return False
    a, b = a.replace("\\", "/"), b.replace("\\", "/")
    return a in b or b in a


def main():
    if not argv:
        print("[OS-COORDINATOR] usage: --expire | --status | --check <module> | --acquire ... | --release ... | --decide ... | --acknowledge ...")
        return
    mode = argv[0]
    d = load()
    leases = d["leases"]

    if mode == "--expire":
        t = now()
        kept = []
        for L in leases:
            exp = L.get("expires")
            if not exp:
                kept.append(L)
                continue
            try:
                et = datetime.fromisoformat(str(exp).replace("Z", "+00:00"))
                if et.tzinfo is None:
                    et = et.replace(tzinfo=timezone.utc)
                if et > t:
                    kept.append(L)
            except ValueError:
                kept.append(L)
        d["leases"] = kept
        save(d)
        print(f"[OS-COORDINATOR] expired removed: {len(leases) - len(kept)}")
        return

    if mode == "--status":
        act = active_leases(leases)
        print("[OS-COORDINATOR] status")
        print(f"  active leases: {len(act)}")
        for L in act:
            print(f"    {L.get('id')} holder={L.get('holder')} module={L.get('module')} until={L.get('expires')}")
        pend = [s for s in d["shared_decisions"] if len(s.get("acknowledged_by") or []) == 0]
        print(f"  pending shared decisions: {len(pend)}")
        for s in pend:
            print(f"    {s.get('id')} — {str(s.get('decision', ''))[:80]}")
        return

    if mode == "--check":
        mod = argv[1] if len(argv) > 1 else ""
        print(f"[OS-COORDINATOR] module: {mod}")
        act = active_leases(leases)
        hit = [L for L in act if glob_overlap(mod, str(L.get("module", ""))) or any(glob_overlap(mod, str(g)) for g in (L.get("blocking") or []))]
        if hit:
            print("  active leases:")
            for L in hit:
                print(f"    {L.get('id')} holder={L.get('holder')} intent={L.get('intent', '')}")
        else:
            print("  active leases: none")
        pend = []
        for s in d["shared_decisions"]:
            aff = s.get("affects") or []
            if any(glob_overlap(mod, str(x)) for x in aff):
                ack = s.get("acknowledged_by") or []
                if len(ack) == 0:
                    pend.append(s)
        if pend:
            print("  pending decisions:")
            for s in pend:
                print(f"    {s.get('id')} — {str(s.get('decision', ''))[:100]}")
                print(f"      acknowledge: bash .claude/scripts/agent-coordinator.sh --acknowledge {s.get('id')} --session \"$(git branch --show-current)-$(date +%H)\"")
        else:
            print("  pending decisions: none")
        return

    if mode == "--acquire":
        try:
            mi = argv.index("--acquire") + 1
            mod = argv[mi]
            typ = argv[argv.index("--type") + 1]
            i0 = argv.index("--intent") + 1
            d0 = argv.index("--duration")
            intent = " ".join(argv[i0:d0])
            minutes = int(argv[d0 + 1])
        except (ValueError, IndexError):
            print("[OS-COORDINATOR] ERROR: --acquire <module> --type READ|WRITE --intent <t> --duration <min>")
            return
        holder = session_id()
        act = active_leases(leases)
        for L in act:
            if L.get("type") == "WRITE" and typ == "WRITE" and glob_overlap(mod, str(L.get("module", ""))):
                print(f"[OS-COORDINATOR] CONFLICT with {L.get('id')} holder={L.get('holder')}")
                return
        lid = next_lease_id(leases)
        acq = now_iso()
        exp = (now() + timedelta(minutes=minutes)).isoformat().replace("+00:00", "Z")
        leases.append(
            {
                "id": lid,
                "holder": holder,
                "module": mod,
                "type": typ,
                "acquired": acq,
                "expires": exp,
                "intent": intent,
                "blocking": [mod, f"{mod.rstrip('/')}/**"],
            }
        )
        d["leases"] = leases
        save(d)
        print(f"[OS-COORDINATOR] ACQUIRED: {lid}")
        return

    if mode == "--release":
        rid = argv[1] if len(argv) > 1 else ""
        nl = [L for L in leases if str(L.get("id")) != rid]
        if len(nl) == len(leases):
            print(f"[OS-COORDINATOR] unknown lease {rid}")
        else:
            d["leases"] = nl
            save(d)
            print(f"[OS-COORDINATOR] RELEASED: {rid}")
        return

    if mode == "--decide":
        try:
            d0 = argv.index("--decide") + 1
            a0 = argv.index("--affects")
            s0 = argv.index("--session")
            txt = " ".join(argv[d0:a0]).strip()
            affects = argv[a0 + 1].split(",")
            sess = argv[s0 + 1]
        except (ValueError, IndexError):
            print("[OS-COORDINATOR] ERROR: --decide <text> --affects <m1,m2> --session <id>")
            return
        sid = next_sd_id(d["shared_decisions"])
        d["shared_decisions"].append(
            {
                "id": sid,
                "decision": txt,
                "made_by": sess,
                "affects": [a.strip() for a in affects if a.strip()],
                "acknowledged_by": [],
                "ts": now_iso(),
            }
        )
        save(d)
        print(f"[OS-COORDINATOR] DECISION RECORDED: {sid}")
        return

    if mode == "--acknowledge":
        try:
            sid = argv[argv.index("--acknowledge") + 1]
            sess = argv[argv.index("--session") + 1]
        except (ValueError, IndexError):
            print("[OS-COORDINATOR] ERROR: --acknowledge <SD-ID> --session <id>")
            return
        for s in d["shared_decisions"]:
            if str(s.get("id")) == sid:
                s.setdefault("acknowledged_by", [])
                if sess not in s["acknowledged_by"]:
                    s["acknowledged_by"].append(sess)
                save(d)
                print(f"[OS-COORDINATOR] ACKNOWLEDGED: {sid} by {sess}")
                return
        print(f"[OS-COORDINATOR] unknown decision {sid}")


try:
    main()
except Exception as e:
    print(f"[OS-COORDINATOR] ERROR: {e}", file=sys.stderr)
PY

exit 0
