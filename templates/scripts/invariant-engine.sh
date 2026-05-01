#!/usr/bin/env bash
# Invariant engine: pattern checks, staleness, lifecycle hints; updates .claude/invariants.json.
# Default exit 0; use --enforce to exit 1 if invariant-report shows violated > 0. LF-only.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

ENFORCE=0
INV_LINES=""
for a in "$@"; do
  if [[ "$a" == "--enforce" ]]; then
    ENFORCE=1
  else
    INV_LINES+="${a}"$'\n'
  fi
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "[OS-INVARIANTS] skip: python3 not available"
  exit 0
fi

export INV_REPO="$REPO_ROOT"
export INV_LINES

python3 - <<'PY'
import glob
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(os.environ["INV_REPO"])
args = [x for x in os.environ.get("INV_LINES", "").splitlines() if x.strip()]
INV_PATH = ROOT / ".claude" / "invariants.json"
REPORT = ROOT / ".claude" / "invariant-report.json"
KG = ROOT / ".claude" / "knowledge-graph.json"
SKIP = {"node_modules", ".git", "dist", ".claude", ".next", "build", "coverage"}


def now_iso():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def load_json(p: Path, default):
    if not p.is_file():
        return default
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return default


def save_json(p: Path, data):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(data, indent=2), encoding="utf-8")


def walk_scope(rel_scope: str):
    base = ROOT / rel_scope.replace("/", os.sep)
    if base.is_file():
        yield base
        return
    if not base.is_dir():
        return
    for p in base.rglob("*"):
        if not p.is_file():
            continue
        if any(x in p.parts for x in SKIP):
            continue
        if p.suffix in {".ts", ".tsx", ".js", ".jsx"}:
            yield p


def glob_scopes(patterns):
    for pat in patterns or []:
        for g in glob.glob(str(ROOT / pat), recursive=True):
            p = Path(g)
            if p.is_file():
                yield p


def check_pattern_count(chk: dict) -> tuple:
    pat = re.compile(chk.get("pattern", "."))
    op = chk.get("operator", ">=")
    exp = int(chk.get("expected", 0))
    scope = chk.get("scope", "")
    n = 0
    files = list(walk_scope(scope)) if scope else []
    for p in files:
        try:
            txt = p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        n += len(pat.findall(txt))
    ok = (op == ">=" and n >= exp) or (op == "<=" and n <= exp) or (op == "==" and n == exp)
    msg = f"{n} matches (expected {op} {exp})"
    return ("PASS", msg) if ok else ("FAIL", msg)


def check_pattern_absent(chk: dict) -> tuple:
    rx = re.compile(chk.get("pattern", "^$"), re.M)
    globs = chk.get("scope_globs") or []
    hits = []
    for p in glob_scopes(globs):
        try:
            txt = p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for m in rx.finditer(txt):
            ln = txt[: m.start()].count("\n") + 1
            rel = p.relative_to(ROOT).as_posix()
            hits.append(f"{rel}:{ln}")
            if len(hits) >= 5:
                break
        if len(hits) >= 5:
            break
    if hits:
        return "FAIL", "; ".join(hits)
    return "PASS", "absent"


def check_file_contains(chk: dict) -> tuple:
    rel = chk.get("file", "")
    req = chk.get("required") or []
    p = ROOT / rel
    if not p.is_file():
        return "FAIL", f"missing file {rel}"
    txt = p.read_text(encoding="utf-8", errors="replace")
    missing = [s for s in req if s not in txt]
    if missing:
        return "FAIL", "missing: " + ", ".join(missing)
    return "PASS", "all required strings present"


def check_env_not_tracked(_chk: dict) -> tuple:
    try:
        cp = subprocess.run(
            ["git", "-C", str(ROOT), "ls-files", "--", ".env", ".env.production", ".env.local"],
            capture_output=True,
            text=True,
            check=False,
        )
        lines = [x.strip() for x in cp.stdout.splitlines() if x.strip()]
        if lines:
            return "FAIL", "tracked env files: " + ", ".join(lines[:5])
        return "PASS", "no .env tracked"
    except Exception as e:
        return "UNKNOWN", str(e)


def check_migration_rollback_coverage(chk: dict) -> tuple:
    """Heuristic: each migration file that declares an `up` path should also declare down/rollback."""
    scope = chk.get("scope", "migrations")
    base = ROOT / str(scope).replace("/", os.sep)
    if not base.is_dir():
        return "PASS", "no migrations directory"
    files = [
        p
        for p in base.rglob("*")
        if p.is_file() and p.suffix in {".ts", ".js", ".sql", ".mts", ".cts"}
        and not any(x in p.parts for x in SKIP)
    ]
    if not files:
        return "PASS", "no migration files"
    up_rx = re.compile(
        r"\bfunction\s+up\b|\basync\s+function\s+up\b|export\s+async\s+function\s+up\b|\bup\s*\(",
        re.I,
    )
    down_rx = re.compile(r"down\s*\(|rollback", re.I)
    n_up = 0
    n_down = 0
    for p in files:
        try:
            txt = p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if up_rx.search(txt):
            n_up += 1
        if down_rx.search(txt):
            n_down += 1
    if n_up == 0:
        return "PASS", "no up-migration pattern matched"
    if n_down >= n_up:
        return "PASS", f"rollback/down coverage: {n_down} signals vs {n_up} up-bearing files"
    return "FAIL", f"rollback/down signals {n_down} < up-bearing files {n_up}"


def check_dependency_absent(chk: dict) -> tuple:
    kg = load_json(KG, {})
    edges = kg.get("edges") or []
    fp = chk.get("from_prefix", "client/")
    tp = chk.get("to_prefix", "server/")
    bad = []
    for e in edges:
        if not isinstance(e, dict):
            continue
        f = str(e.get("from", ""))
        t = str(e.get("to", ""))
        if f.startswith(fp) and t.startswith(tp):
            bad.append(f"{f} → {t}")
        if f.startswith("server/") and t.startswith("client/"):
            bad.append(f"{f} → {t}")
    if bad:
        return "FAIL", bad[0]
    return "PASS", "no forbidden client↔server edges"


def run_check(inv: dict) -> tuple:
    chk = inv.get("check") or {}
    t = chk.get("type")
    if t == "pattern_count":
        return check_pattern_count(chk)
    if t == "pattern_absent":
        return check_pattern_absent(chk)
    if t == "file_contains":
        return check_file_contains(chk)
    if t == "env_not_tracked":
        return check_env_not_tracked(chk)
    if t == "dependency_absent":
        return check_dependency_absent(chk)
    if t == "migration_rollback_coverage":
        return check_migration_rollback_coverage(chk)
    return "UNKNOWN", f"unknown check type {t}"


def staleness_for(inv: dict) -> tuple:
    chk = inv.get("check") or {}
    paths = []
    if chk.get("scope"):
        base = ROOT / str(chk["scope"]).replace("/", os.sep)
        if base.is_dir():
            for p in base.rglob("*.ts"):
                if not any(x in p.parts for x in SKIP):
                    paths.append(str(p.relative_to(ROOT)).replace("\\", "/"))
        elif base.is_file():
            paths.append(str(base.relative_to(ROOT)).replace("\\", "/"))
    for g in chk.get("scope_globs") or []:
        for p in glob.glob(str(ROOT / g), recursive=True):
            po = Path(p)
            if po.is_file():
                paths.append(po.relative_to(ROOT).as_posix())
    lv = inv.get("last_verified")
    if not lv or not paths:
        return "FRESH", "LOW"
    try:
        since = datetime.fromisoformat(str(lv).replace("Z", "+00:00"))
    except ValueError:
        return "FRESH", "LOW"
    n = 0
    try:
        cp = subprocess.run(
            ["git", "-C", str(ROOT), "log", f"--since={since.isoformat()}", "--oneline", "--"] + paths[:60],
            capture_output=True,
            text=True,
            check=False,
        )
        n = len([l for l in cp.stdout.splitlines() if l.strip()])
    except Exception:
        pass
    risk = "LOW"
    if n >= 3:
        risk = "HIGH"
    elif n >= 1:
        risk = "MEDIUM"
    if n > 0:
        return "STALE", risk
    return "FRESH", risk


def lifecycle_obsolete(inv: dict):
    chk = inv.get("check") or {}
    if chk.get("type") == "pattern_count":
        scope = chk.get("scope", "")
        base = ROOT / scope.replace("/", os.sep)
        if scope and not base.exists():
            return "module path missing — OBSOLETE candidate"
    return None


def main():
    mode = "--verify-all"
    if "--verify" in args:
        mode = "--verify"
    elif "--staleness" in args:
        mode = "--staleness"
    elif "--lifecycle" in args:
        mode = "--lifecycle"
    vid = None
    if mode == "--verify":
        i = args.index("--verify")
        vid = args[i + 1] if i + 1 < len(args) else None

    data = load_json(INV_PATH, {"schemaVersion": 1, "invariants": []})
    invs = data.get("invariants")
    if not isinstance(invs, list):
        print("[OS-INVARIANTS] ERROR: invariants.json must contain invariants array")
        return

    if mode == "--staleness":
        print("[OS-INVARIANTS] staleness scan")
        for inv in invs:
            if str(inv.get("status", "")).upper() == "OBSOLETE":
                continue
            st, risk = staleness_for(inv)
            if st == "STALE":
                inv["status"] = "STALE"
                inv["staleness_risk"] = risk
                inv["evidence"] = f"git churn since last_verified ({risk})"
        save_json(INV_PATH, data)
        print("  STALE flags updated from git history")
        return

    if mode == "--lifecycle":
        print("[OS-INVARIANTS] lifecycle hints")
        for inv in invs:
            h = lifecycle_obsolete(inv)
            if h:
                print(f"  {inv.get('id')}: {h}")
        return

    to_run = []
    for inv in invs:
        if str(inv.get("status", "")).upper() == "OBSOLETE":
            continue
        if mode == "--verify-all":
            to_run.append(inv)
        elif vid and inv.get("id") == vid:
            to_run.append(inv)

    print(f"[OS-INVARIANTS] verifying {len(to_run)} invariants...")
    details = []
    counts = {"VERIFIED": 0, "VIOLATED": 0, "STALE": 0, "UNKNOWN": 0}
    ts = now_iso()
    for inv in to_run:
        iid = inv.get("id", "?")
        name = inv.get("name", "")
        st_churn, risk = staleness_for(inv)
        res, msg = run_check(inv)
        if res == "FAIL":
            inv["status"] = "VIOLATED"
            inv["evidence"] = msg
            inv["staleness_risk"] = risk if st_churn == "STALE" else "LOW"
            counts["VIOLATED"] += 1
            sev = inv.get("violation_severity", "WARN")
            print(f"    {iid} {name}: VIOLATED")
            print(f"      {msg} — severity {sev}")
        elif res == "UNKNOWN":
            inv["status"] = "UNKNOWN"
            inv["evidence"] = msg
            counts["UNKNOWN"] += 1
            print(f"    {iid} {name}: UNKNOWN ({msg})")
        elif st_churn == "STALE":
            inv["status"] = "STALE"
            inv["staleness_risk"] = risk
            inv["evidence"] = f"STALE ({risk}) but check: {msg}"
            inv["last_verified"] = ts[:10]
            counts["STALE"] += 1
            print(f"    {iid} {name}: STALE (git churn since last verify — {risk})")
        else:
            inv["status"] = "VERIFIED"
            inv["last_verified"] = ts[:10]
            inv["evidence"] = msg
            inv["staleness_risk"] = "LOW"
            counts["VERIFIED"] += 1
            print(f"    {iid} {name}: VERIFIED ({msg})")
        details.append({"id": iid, "status": inv.get("status"), "detail": inv.get("evidence")})

    save_json(INV_PATH, data)
    print(
        f"  summary: {counts['VERIFIED']} VERIFIED, {counts['STALE']} STALE, {counts['VIOLATED']} VIOLATED, {counts['UNKNOWN']} UNKNOWN"
    )
    if counts["VIOLATED"]:
        print("  VIOLATED invariants require resolution before Critical mode work")

    save_json(
        REPORT,
        {
            "ts": ts,
            "verified": counts["VERIFIED"],
            "stale": counts["STALE"],
            "violated": counts["VIOLATED"],
            "unknown": counts["UNKNOWN"],
            "details": details,
        },
    )


try:
    main()
except Exception as e:
    print(f"[OS-INVARIANTS] ERROR: {e}", file=sys.stderr)
PY

if [[ "$ENFORCE" -eq 1 ]] && [[ -f "${REPO_ROOT}/.claude/invariant-report.json" ]]; then
  python3 - <<'PY' || exit 1
import json, sys
from pathlib import Path
p = Path(".claude/invariant-report.json")
d = json.loads(p.read_text(encoding="utf-8"))
sys.exit(1 if d.get("violated", 0) > 0 else 0)
PY
fi

exit 0
