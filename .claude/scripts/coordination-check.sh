#!/usr/bin/env bash
# Multi-agent coordination — leases, intentions, shared decisions vs paths (optimistic, non-blocking).
# State file: .claude/agent-state.json. H10: LF-only; exit 0.
set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

echo "[OS-COORDINATION]"

if ! command -v python3 >/dev/null 2>&1; then
  echo "  skip: python3 not available"
  exit 0
fi

export AGENT_STATE_PATH="${AGENT_STATE_PATH:-${REPO_ROOT}/.claude/agent-state.json}"

python3 - "$@" <<'PY'
import fnmatch
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO = Path.cwd()
STATE_PATH = Path(os.environ.get("AGENT_STATE_PATH", str(REPO / ".claude" / "agent-state.json"))).expanduser().resolve()
REPORT_PATH = REPO / ".claude" / "coordination-report.json"


def parse_iso(s):
    if not s or not isinstance(s, str):
        return None
    t = s.strip()
    if t.endswith("Z"):
        t = t[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(t)
    except ValueError:
        return None


def now_utc():
    return datetime.now(timezone.utc)


def norm_rel(p: str) -> str:
    return p.replace("\\", "/").strip().lstrip("./")


def match_affect_pattern(rel: str, pat: str) -> bool:
    rel = norm_rel(rel)
    pat = norm_rel(pat)
    if pat.endswith("/**"):
        root = pat[:-3].rstrip("/")
        return rel == root or rel.startswith(root + "/")
    if "**" in pat:
        return fnmatch.fnmatch(rel, pat.replace("**", "*"))
    return fnmatch.fnmatch(rel, pat) or rel == pat


def paths_from_env() -> list[str]:
    raw = os.environ.get("COORDINATION_PATHS", "").strip()
    if not raw:
        return []
    return [norm_rel(x) for x in raw.split(",") if x.strip()]


def paths_from_git() -> list[str]:
    out = set()
    try:
        for cmd in (
            ["git", "-C", str(REPO), "diff", "--name-only", "HEAD"],
            ["git", "-C", str(REPO), "diff", "--name-only", "--cached"],
        ):
            p = subprocess.run(cmd, capture_output=True, text=True, check=False)
            for line in p.stdout.splitlines():
                line = line.strip()
                if line:
                    out.add(norm_rel(line))
        p = subprocess.run(
            ["git", "-C", str(REPO), "ls-files", "-mo", "--exclude-standard"],
            capture_output=True,
            text=True,
            check=False,
        )
        for line in p.stdout.splitlines():
            line = line.strip()
            if line:
                out.add(norm_rel(line))
    except FileNotFoundError:
        pass
    return sorted(out)


def lease_active(lease: dict, now) -> bool:
    exp = parse_iso(lease.get("expires") or "")
    if exp and now > exp.astimezone(timezone.utc):
        return False
    return True


def minutes_left(expires_iso: str, now) -> str:
    exp = parse_iso(expires_iso or "")
    if not exp:
        return "unknown"
    delta = exp.astimezone(timezone.utc) - now
    if delta.total_seconds() <= 0:
        return "0"
    return str(int(delta.total_seconds() // 60))


def path_hits_lease(rel: str, lease: dict) -> bool:
    for pat in lease.get("blocking") or []:
        if isinstance(pat, str) and match_affect_pattern(rel, pat):
            return True
    mod = lease.get("module") or ""
    if isinstance(mod, str) and mod.strip():
        m = norm_rel(mod)
        if rel == m or rel.startswith(m.rstrip("/") + "/"):
            return True
    return False


def path_hits_any_pattern(rel: str, patterns: list) -> bool:
    for pat in patterns or []:
        if isinstance(pat, str) and match_affect_pattern(rel, pat):
            return True
    return False


def dedupe_shared(hits: list) -> list:
    out = {}
    for _, s in hits:
        k = s.get("id")
        if k is None:
            k = f"_anon_{len(out)}"
        out[k] = s
    return list(out.values())


def main():
    args = sys.argv[1:]
    paths_arg = None
    if "--paths" in args:
        i = args.index("--paths")
        paths_arg = args[i + 1] if i + 1 < len(args) else ""

    wt = os.environ.get("COORDINATION_WT", "").strip() in ("1", "true", "yes")
    session = os.environ.get("COORDINATION_SESSION", "").strip()

    if paths_arg is not None:
        paths = [norm_rel(x) for x in paths_arg.split(",") if x.strip()]
    else:
        paths = paths_from_env()
        if wt and not paths:
            paths = paths_from_git()

    if not STATE_PATH.is_file():
        print(f"  skip: no {STATE_PATH.name} (bootstrap copies agent-state.seed.json)")
        return

    try:
        state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        print("  skip: agent-state.json is not valid JSON")
        return

    leases = [x for x in (state.get("leases") or []) if isinstance(x, dict)]
    intentions = [x for x in (state.get("intentions") or []) if isinstance(x, dict)]
    shared = [x for x in (state.get("shared_decisions") or []) if isinstance(x, dict)]

    now = now_utc()
    active_leases = []
    for L in leases:
        if not lease_active(L, now):
            continue
        holder = str(L.get("holder", ""))
        if session and holder == session:
            continue
        active_leases.append(L)

    conflicts = []
    shared_hits = []
    intention_hits = []

    for rel in paths:
        for L in active_leases:
            if path_hits_lease(rel, L):
                conflicts.append({"path": rel, "lease": L})
        for sd in shared:
            affects = sd.get("affects") or []
            if path_hits_any_pattern(rel, affects):
                shared_hits.append((rel, sd))
        for it in intentions:
            mod = (it.get("module") or "").strip()
            if not mod:
                continue
            m = norm_rel(mod)
            if not (rel == m or rel.startswith(m.rstrip("/") + "/")):
                continue
            cw = it.get("conflict_with") or []
            active_ids = {str(x.get("id")) for x in active_leases}
            if any(cid in active_ids for cid in cw if isinstance(cid, str)):
                intention_hits.append((rel, it))

    report = {
        "ts": now.isoformat().replace("+00:00", "Z"),
        "paths_checked": paths,
        "session": session or None,
        "active_leases": [{"id": x.get("id"), "holder": x.get("holder")} for x in active_leases],
        "conflicts": [
            {"path": c["path"], "lease_id": c["lease"].get("id"), "holder": c["lease"].get("holder")}
            for c in conflicts
        ],
        "shared_decisions_applicable": list(
            {
                sd.get("id"): sd
                for _, sd in shared_hits
                if sd.get("id")
            }.values()
        ),
        "intentions_blocked": [{"path": p, "id": it.get("id")} for p, it in intention_hits],
    }
    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text(json.dumps(report, indent=2), encoding="utf-8")

    if not paths:
        print("  hint: no paths to check — set COORDINATION_PATHS, pass --paths, or COORDINATION_WT=1 (git WT)")
        if shared:
            print(f"  info: {len(shared)} shared decision(s) registered in {STATE_PATH.name}")
        try:
            rprel = REPORT_PATH.relative_to(REPO)
        except ValueError:
            rprel = REPORT_PATH
        print(f"  report: {rprel}")
        return

    if conflicts or intention_hits:
        print("  CONFLICT DETECTED")
        seen = set()
        for c in conflicts:
            L = c["lease"]
            key = (c["path"], L.get("id"))
            if key in seen:
                continue
            seen.add(key)
            print(f"    path: {c['path']}")
            print(f"    active lease: {L.get('id')} (holder={L.get('holder')}) intent={L.get('intent', '')}")
            exp = L.get("expires")
            if exp:
                print(f"    expires in ~{minutes_left(str(exp), now)} minutes ({exp})")
        for rel, it in intention_hits:
            print(f"    intention {it.get('id')} on {rel} — status={it.get('status', '')}")
        for sd in dedupe_shared(shared_hits):
            print(f"    shared decision {sd.get('id')}: {sd.get('decision', '')[:120]}")
        print("  Options:")
        print("    1. Align work with active shared decisions / leases (document in session-state)")
        print("    2. Coordinate with lease holder (update agent-state.json or wait for expiry)")
        print("    3. Challenge: propose change via PR + update shared_decisions after agreement")
    else:
        if shared_hits:
            print("  NOTICE: shared architectural decision(s) apply to your paths — stay consistent:")
            for sd in dedupe_shared(shared_hits):
                print(f"    {sd.get('id')}: {sd.get('decision', '')[:160]}")
        else:
            print("  OK: no lease conflict for checked paths")

    try:
        rprel = REPORT_PATH.relative_to(REPO)
    except ValueError:
        rprel = REPORT_PATH
    print(f"  report: {rprel}")


if __name__ == "__main__":
    main()
PY

exit 0
