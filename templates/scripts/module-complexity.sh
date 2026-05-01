#!/usr/bin/env bash
# Module complexity from git history + optional scan from risk-surfaces.json. H10: LF-only; exit 0.
set -euo pipefail

echo "[OS-MODULE-COMPLEXITY]"

if ! command -v python3 >/dev/null 2>&1; then
  echo "  skip: python3 not available"
  exit 0
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "  skip: not a git repository"
  exit 0
fi

python3 - "$@" <<'PY'
import json, subprocess, sys
from datetime import datetime, timezone
from pathlib import Path


def git_count(cmd: list[str]) -> int:
    try:
        out = subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL)
        return len([l for l in out.splitlines() if l.strip()])
    except subprocess.CalledProcessError:
        return 0


def git_text(cmd: list[str]) -> str:
    try:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL).strip()
    except subprocess.CalledProcessError:
        return ""


def analyze_file(path: str, days: int = 90) -> dict:
    since = f"{days} days ago"
    churn = git_count(
        ["git", "log", "--since", since, "--oneline", "--follow", "--", path]
    )
    # Bug density: all history on path (spec: no --since on this metric)
    bugs = git_count(
        [
            "git",
            "log",
            "--oneline",
            "--follow",
            "--grep=fix",
            "--grep=bug",
            "--grep=hotfix",
            "--grep=patch",
            "--grep=revert",
            "--regexp-ignore-case",
            "--",
            path,
        ]
    )
    # Author count: all unique authors ever on path (spec: no --since)
    authors_out = git_text(
        ["git", "log", "--format=%ae", "--follow", "--", path]
    )
    authors = len({l for l in authors_out.splitlines() if l.strip()}) if authors_out else 0
    last = git_text(["git", "log", "-1", "--format=%cr", "--", path]) or "unknown"
    # Incident proximity (spec: oneline + grep, no --follow)
    inc = git_count(
        [
            "git",
            "log",
            "--oneline",
            "--grep=incident",
            "--grep=hotfix",
            "--grep=emergency",
            "--grep=sev[0-9]",
            "--regexp-ignore-case",
            "--",
            path,
        ]
    )

    score = 0
    churn_l = "LOW (+1)"
    if churn >= 20:
        score += 3
        churn_l = "HIGH (+3)"
    elif churn >= 10:
        score += 2
        churn_l = "MEDIUM (+2)"
    else:
        score += 1

    bug_l = "LOW (+1)"
    if bugs >= 5:
        score += 3
        bug_l = "HIGH (+3)"
    elif bugs >= 2:
        score += 2
        bug_l = "MEDIUM (+2)"
    else:
        score += 1

    inc_l = "none (+0)"
    if inc >= 1:
        score += 3
        inc_l = f"HIGH (+3)"

    auth_note = ""
    if authors >= 3:
        score += 1
        auth_note = " (+1 authors>=3)"

    if score >= 8:
        level = "CRITICAL"
        rec = "escalate to Opus regardless of task type"
    elif score >= 5:
        level = "ELEVATED"
        rec = "recommend Opus for any non-trivial change"
    elif score >= 3:
        level = "MODERATE"
        rec = "standard model selection applies"
    else:
        level = "LOW"
        rec = "standard model selection applies"

    return {
        "path": path,
        "churn": churn,
        "churn_label": churn_l,
        "bugs": bugs,
        "bug_label": bug_l,
        "authors": authors,
        "incident": inc,
        "inc_label": inc_l,
        "last": last,
        "score": score,
        "level": level,
        "recommendation": rec,
        "auth_note": auth_note,
    }


def print_report(m: dict):
    p = m["path"]
    print(f"  file: {p}")
    print(f"    churn (90d)   : {m['churn']} commits — {m['churn_label']}")
    print(f"    bug density   : {m['bugs']} commits  — {m['bug_label']}")
    print(f"    authors       : {m['authors']}")
    print(f"    incident prox : {m['incident']}          — {m['inc_label']}{m['auth_note']}")
    print("    ──────────────────────────")
    print(f"    score         : {m['score']} — {m['level']}")
    print(f"    recommendation: {m['recommendation']}")
    print(f"    note          : this file has elevated risk profile from git history")
    print(f"    last modified : {m['last']}")


def cmd_scan():
    rp = Path(".claude/risk-surfaces.json")
    if not rp.is_file():
        print("  skip: no .claude/risk-surfaces.json (run risk-surface-scan.sh first)")
        return
    try:
        data = json.loads(rp.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"  skip: invalid risk-surfaces.json ({e})")
        return
    # Spec: declared + detected only (not undeclared-only paths)
    paths = set(data.get("declared") or [])
    for item in data.get("detected") or []:
        if isinstance(item, dict) and item.get("path"):
            paths.add(item["path"])
    rows = []
    for p in sorted(paths):
        if not Path(p).is_file() and not Path(p).exists():
            # skip dirs or missing
            try:
                subprocess.check_call(
                    ["git", "cat-file", "-e", f"HEAD:{p}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
                )
            except Exception:
                continue
        m = analyze_file(p)
        rows.append(m)
    rows.sort(key=lambda x: -x["score"])
    print("  [OS-MODULE-COMPLEXITY] scan complete")
    for m in rows[:25]:
        print(f"    {m['level']:8s}: {m['path']} (score: {m['score']})")
    if len(rows) > 25:
        print(f"    ... {len(rows) - 25} more paths omitted")
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    out = {
        "scanned_at": ts,
        "files": [
            {
                "path": m["path"],
                "score": m["score"],
                "level": m["level"],
                "churn": m["churn"],
                "bug_density": m["bugs"],
                "authors": m["authors"],
            }
            for m in rows
        ],
    }
    Path(".claude").mkdir(exist_ok=True)
    Path(".claude/complexity-map.json").write_text(json.dumps(out, indent=2), encoding="utf-8")
    print(f"  wrote .claude/complexity-map.json ({len(rows)} files)")


def main():
    a = sys.argv[1:]
    if a and a[0] == "--scan":
        cmd_scan()
        return
    if not a:
        print("  usage: module-complexity.sh <filepath>")
        print("         module-complexity.sh --scan")
        return
    path = a[0]
    m = analyze_file(path)
    print(f"[OS-MODULE-COMPLEXITY] {path}")
    print(f"  churn (90d)   : {m['churn']} commits — {m['churn_label']}")
    print(f"  bug density   : {m['bugs']} commits  — {m['bug_label']}")
    print(f"  authors       : {m['authors']}")
    print(f"  incident prox : {m['incident']}          — {m['inc_label']}{m['auth_note']}")
    print("  ──────────────────────────")
    print(f"  score         : {m['score']} — {m['level']}")
    print(f"  recommendation: {m['recommendation']}")
    print(f"  note          : this file has elevated risk profile from git history")
    print(f"  last modified : {m['last']}")


if __name__ == "__main__":
    main()
PY

exit 0
