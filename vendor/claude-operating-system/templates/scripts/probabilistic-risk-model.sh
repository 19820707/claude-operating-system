#!/usr/bin/env bash
# Probabilistic risk model — git-calibrated P(incident), P(regression|coverage), blast stats. H10: LF-only; exit 0.
set -euo pipefail

echo "[OS-RISK-MODEL]"

if ! command -v python3 >/dev/null 2>&1; then
  echo "  skip: python3 not available"
  exit 0
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "  skip: not a git repository"
  exit 0
fi

python3 - "$@" <<'PY'
import json
import math
import re
import subprocess
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

DAYS = 180
INCIDENT_RX = re.compile(
    r"hotfix|incident|emergency|sev[0-9]|\brevert\b", re.I
)
FIX_RX = re.compile(
    r"\bfix\b|\bbug\b|\bhotfix\b|\bpatch\b|\bregression\b|\brevert\b", re.I
)


def git_lines(cmd: list[str], cwd: Path) -> str:
    try:
        return subprocess.check_output(cmd, cwd=str(cwd), text=True, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        return ""


def file_to_module(rel: str) -> str:
    rel = rel.replace("\\", "/").strip("/")
    parts = rel.split("/")
    if len(parts) >= 2 and parts[0] in ("server", "client", "shared"):
        return f"{parts[0]}/{parts[1]}"
    if parts[0] == "src" and len(parts) >= 2:
        return f"src/{parts[1]}"
    if parts:
        return parts[0]
    return "."


def load_arch_edges(repo: Path) -> list[tuple[str, str]]:
    p = repo / ".claude" / "architecture-graph.json"
    if not p.is_file():
        return []
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return []
    out = []
    for e in data.get("module_edges") or []:
        if isinstance(e, dict) and e.get("from") and e.get("to"):
            out.append((str(e["from"]), str(e["to"])))
    return out


def build_reverse(edges: list[tuple[str, str]]) -> dict[str, list[str]]:
    rev: dict[str, list[str]] = defaultdict(list)
    for a, b in edges:
        rev[b].append(a)
    return rev


def transitive_importer_count(rev: dict[str, list[str]], target: str) -> int:
    seen = {target}
    stack = [target]
    while stack:
        cur = stack.pop()
        for pred in rev.get(cur, ()):
            if pred not in seen:
                seen.add(pred)
                stack.append(pred)
    return max(0, len(seen) - 1)


def parse_numstat_total(show_out: str, module_prefix: str) -> int:
    tot = 0
    mp = (module_prefix or "").rstrip("/")
    for line in show_out.splitlines():
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        fp = parts[2].replace("\\", "/")
        if mp and not (fp == mp or fp.startswith(mp + "/")):
            continue
        try:
            a, b = parts[0], parts[1]
            if a == "-" and b == "-":
                continue
            tot += int(a or 0) + int(b or 0)
        except ValueError:
            continue
    return tot


def commits_touching(repo: Path, pathspec: str, since_days: int) -> list[tuple[str, str]]:
    out = git_lines(
        [
            "git",
            "log",
            "--since",
            f"{since_days} days ago",
            "--format=%H\t%s",
            "--",
            pathspec,
        ],
        repo,
    )
    rows = []
    for line in out.splitlines():
        line = line.strip()
        if "\t" not in line:
            continue
        h, subj = line.split("\t", 1)
        if len(h) >= 7:
            rows.append((h, subj))
    return rows


def find_coverage_pct(repo: Path) -> float | None:
    candidates = [
        repo / "coverage" / "coverage-summary.json",
        repo / "coverage" / "coverage-final.json",
    ]
    for p in candidates:
        if not p.is_file():
            continue
        try:
            j = json.loads(p.read_text(encoding="utf-8"))
            tot = j.get("total") or {}
            lines = tot.get("lines") or {}
            if "pct" in lines:
                return float(lines["pct"])
        except Exception:
            continue
    return None


def risk_label_p_inc(p: float) -> str:
    if p >= 0.30:
        return "ELEVATED"
    if p >= 0.15:
        return "MODERATE"
    return "LOW"


def risk_label_p_reg(p: float) -> str:
    if p >= 0.55:
        return "HIGH"
    if p >= 0.35:
        return "MODERATE"
    return "LOW"


def change_lines_default(repo: Path, rel_file: str | None) -> int:
    if rel_file:
        stat = git_lines(["git", "diff", "--numstat", "HEAD", "--", rel_file], repo)
        if stat.strip():
            t = 0
            for line in stat.splitlines():
                ps = line.split("\t")
                if len(ps) >= 3:
                    try:
                        t += int(ps[0] or 0) + int(ps[1] or 0)
                    except ValueError:
                        pass
            if t > 0:
                return t
    st = git_lines(["git", "show", "--format=", "--numstat", "-1", "HEAD"], repo)
    t = 0
    for line in st.splitlines():
        ps = line.split("\t")
        if len(ps) >= 3:
            try:
                t += int(ps[0] or 0) + int(ps[1] or 0)
            except ValueError:
                pass
    return max(1, t)


def main():
    args = sys.argv[1:]
    repo = Path.cwd().resolve()
    mod = None
    rel_file = None
    change_override = None
    i = 0
    while i < len(args):
        if args[i] == "--file" and i + 1 < len(args):
            rel_file = args[i + 1].replace("\\", "/")
            mod = file_to_module(rel_file)
            i += 2
        elif args[i] == "--module" and i + 1 < len(args):
            mod = args[i + 1].strip().replace("\\", "/")
            i += 2
        elif args[i] == "--change-lines" and i + 1 < len(args):
            change_override = int(args[i + 1])
            i += 2
        else:
            i += 1

    if not mod:
        print("  usage: probabilistic-risk-model.sh --file <path> | --module <server/auth>")
        print("         [--change-lines N]")
        return

    pathspec = mod.rstrip("/") + "/"
    rows = commits_touching(repo, pathspec, DAYS)
    total = len(rows)
    inc_n = sum(1 for _, s in rows if INCIDENT_RX.search(s))
    fix_n = sum(1 for _, s in rows if FIX_RX.search(s))

    # Laplace-smoothed P(incident proxy): volatile production signals / exposure
    p_inc = (inc_n + 0.6) / (total + 1.8) if total else 0.12
    p_inc = min(0.95, p_inc)

    cov = find_coverage_pct(repo)
    cov_use = float(cov) if cov is not None else 48.0
    fix_ratio = (fix_n + 0.5) / (total + 1.0) if total else 0.1
    p_reg = 0.38 * min(1.0, fix_ratio * 1.4) + 0.62 * max(0.05, 1.0 - cov_use / 100.0)
    p_reg = min(0.92, p_reg)

    edges = load_arch_edges(repo)
    rev = build_reverse(edges)
    base_blast = transitive_importer_count(rev, mod) if rev else 0

    blast_samples: list[int] = []
    line_samples: list[int] = []
    if rev:
        for h, _subj in rows[:36]:
            show = git_lines(["git", "show", "--format=", "--numstat", h], repo)
            lines = parse_numstat_total(show, pathspec)
            line_samples.append(max(1, lines))
            touched_mods = set()
            for line in show.splitlines():
                ps = line.split("\t")
                if len(ps) >= 3:
                    touched_mods.add(file_to_module(ps[2].replace("\\", "/")))
            touched_mods.discard(".")
            if not touched_mods:
                touched_mods.add(mod)
            bmax = 0
            for m in touched_mods:
                bmax = max(bmax, transitive_importer_count(rev, m))
            blast_samples.append(bmax)

    ch_lines = change_override if change_override is not None else change_lines_default(repo, rel_file)

    if blast_samples:
        mean_b = sum(blast_samples) / len(blast_samples)
        var = sum((x - mean_b) ** 2 for x in blast_samples) / max(1, len(blast_samples) - 1)
        sigma_b = math.sqrt(var) if len(blast_samples) > 1 else 2.1
    else:
        # Heuristic when import graph missing: scale with churn + change size
        mean_b = min(18.0, 2.2 + (total * 0.35) + min(6.0, ch_lines / 90.0))
        sigma_b = 2.2
        blast_samples = [int(round(mean_b))] * min(5, max(1, min(total, 5)))
    # Bucket-conditioned mean (coarse)
    def bucket(ln: int) -> str:
        if ln < 30:
            return "s"
        if ln < 120:
            return "m"
        if ln < 400:
            return "l"
        return "xl"

    pairs = list(zip(line_samples, blast_samples)) if line_samples else []
    b_cur = bucket(ch_lines)
    sub = [b for ln, b in pairs if bucket(ln) == b_cur]
    exp_blast = sum(sub) / len(sub) if sub else mean_b
    if not sub and pairs:
        exp_blast = mean_b

    comp = min(
        1.0,
        0.42 * p_inc + 0.33 * p_reg + 0.25 * min(1.0, exp_blast / 16.0),
    )

    if comp >= 0.62 or p_inc >= 0.32:
        rec = "Opus mandatory — treat as production-impacting change; add tests before merge"
    elif comp >= 0.44 or p_reg >= 0.52:
        rec = "Opus recommended for non-trivial edits; increase regression coverage on touched paths"
    else:
        rec = "Standard model selection; keep monitoring historical incident rate"

    cov_hint = ""
    if cov is not None and p_reg >= 0.45:
        cov_hint = f"; minimum line coverage target ~{min(85, int(cov_use) + 25)}% on this surface if merging soon"

    target = rel_file or mod
    print(f"  target: {target}")
    print(f"  module: {mod}")
    print(
        f"  P(incident)            : {p_inc:.2f} — {risk_label_p_inc(p_inc)} (historical: {inc_n} volatile commits in {total} changes)"
    )
    print(
        f"  P(regression|coverage) : {p_reg:.2f} — {risk_label_p_reg(p_reg)} (coverage: {cov_use:.0f}%{' measured' if cov is not None else ' prior — no coverage-summary.json'}; {fix_n} fix-like / {total} changes)"
    )
    print(
        f"  expected blast radius  : {exp_blast:.1f} modules (σ={sigma_b:.1f}, based on {len(blast_samples)} historical commits)"
    )
    print(f"  change size (lines)    : {ch_lines}")
    print(f"  composite risk score   : {comp:.2f}")
    print(f"  recommendation         : {rec}{cov_hint}")
    print(
        f"  calibration            : last {DAYS} days on `{pathspec}`; graph={'loaded' if edges else 'absent (run living-arch-graph.sh)'}"
    )

    out = {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "module": mod,
        "file": rel_file,
        "window_days": DAYS,
        "commits_sampled": total,
        "volatile_commits": inc_n,
        "fix_like_commits": fix_n,
        "p_incident": round(p_inc, 4),
        "p_regression_cond_coverage": round(p_reg, 4),
        "coverage_pct_measured": cov,
        "coverage_pct_used": round(cov_use, 2),
        "expected_blast_modules": round(exp_blast, 3),
        "blast_sigma": round(sigma_b, 3),
        "change_lines": ch_lines,
        "composite": round(comp, 4),
        "recommendation": rec,
        "graph_loaded": bool(edges),
    }
    outp = repo / ".claude" / "risk-model.json"
    outp.parent.mkdir(parents=True, exist_ok=True)
    outp.write_text(json.dumps(out, indent=2), encoding="utf-8")
    print(f"  wrote {outp.as_posix()}")


if __name__ == "__main__":
    main()
PY

exit 0
