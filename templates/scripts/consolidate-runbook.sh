#!/usr/bin/env bash
# Procedural Runbook Consolidation — derives .claude/runbooks/<slug>.md from decision-log,
# learning-log, invariants, and epistemic-state (evidence-backed procedural memory). Exit 0; LF-only.
set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT" || exit 0

usage() {
  cat <<'U' >&2
Usage: consolidate-runbook.sh --module <repo-relative-path>
  Example: --module server/auth/index.ts
  Writes: .claude/runbooks/<slug>.md and .claude/runbooks/<slug>.meta.json
U
}

MODULE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --module) MODULE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[OS-RUNBOOK] unknown arg: $1" >&2; usage; exit 0 ;;
  esac
done

if [[ -z "$MODULE" ]]; then
  usage
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[OS-RUNBOOK] skip: python3 not available"
  exit 0
fi

export RB_REPO="$REPO_ROOT"
export RB_MODULE="$MODULE"

python3 - <<'PY'
from __future__ import annotations

import json
import os
import re
import subprocess
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(os.environ["RB_REPO"])
mod_raw = (os.environ.get("RB_MODULE") or "").strip().replace("\\", "/")


def slug_from_module(m: str) -> str:
    p = m.strip().replace("\\", "/")
    low = p.lower()
    for suf in (".ts", ".tsx", ".mts", ".cts"):
        if low.endswith(suf):
            p = p[: -len(suf)]
            break
    s = re.sub(r"[^a-zA-Z0-9/]+", "-", p)
    s = s.replace("/", "-").strip("-").lower()
    return re.sub(r"-+", "-", s) or "module"


def row_touches_module(row: dict, needle: str) -> bool:
    if not needle:
        return False
    blob = json.dumps(row, ensure_ascii=False).lower()
    return needle.lower() in blob


def inv_touches_module(inv: dict, needle: str) -> bool:
    chk = inv.get("check") or {}
    n = needle.lower()
    if chk.get("type") == "dependency_absent" and (
        n.startswith("client/") or n.startswith("server/")
    ):
        return True
    sc = chk.get("scope")
    if isinstance(sc, str) and sc:
        scn = sc.lower().replace("\\", "/").rstrip("/")
        if n == scn or n.startswith(scn + "/"):
            return True
    for g in chk.get("scope_globs") or []:
        if not isinstance(g, str):
            continue
        g = g.replace("\\", "/")
        prefix = g.split("*")[0].lower().rstrip("/")
        if prefix and (n == prefix or n.startswith(prefix + "/")):
            return True
    return False


def is_success_signal(row: dict) -> bool:
    dec = str(row.get("decision", "") or "")
    trig = str(row.get("trigger", "") or "")
    blob = (dec + " " + trig).lower()
    if re.search(r"\brevert(ed|ing)?\b|\brollback\b|\bincident\b|\bhotfix\b", blob):
        return False
    if row.get("type") == "risk_acceptance" and str(row.get("confidence", "")).upper() == "LOW":
        return False
    return True


def main():
    if not mod_raw:
        print("[OS-RUNBOOK] ERROR: empty module")
        return
    slug = slug_from_module(mod_raw)
    needle = mod_raw
    dir_guess = str(Path(mod_raw).parent.as_posix()) if "/" in mod_raw else mod_raw

    decisions = []
    log_path = ROOT / ".claude" / "decision-log.jsonl"
    if log_path.is_file():
        for line in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            if row_touches_module(row, needle):
                decisions.append(row)

    def parse_row_ts(row):
        ts = row.get("ts") or ""
        if not isinstance(ts, str) or not ts.strip():
            return None
        try:
            s = ts.strip()
            if s.endswith("Z"):
                s = s[:-1] + "+00:00"
            return datetime.fromisoformat(s.replace("Z", "+00:00"))
        except Exception:
            return None

    cutoff = datetime.now(timezone.utc) - timedelta(days=180)
    decisions = [r for r in decisions if (t := parse_row_ts(r)) is None or t >= cutoff]

    successes = sum(1 for r in decisions if is_success_signal(r))
    total = len(decisions)

    def git_commit_stats(path: str) -> tuple[int, int]:
        try:
            cp = subprocess.run(
                [
                    "git",
                    "-C",
                    str(ROOT),
                    "log",
                    "--since=180 days ago",
                    "--oneline",
                    "--",
                    path,
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            lines = [ln for ln in (cp.stdout or "").strip().splitlines() if ln.strip()]
        except Exception:
            return 0, 0
        n_tot = len(lines)
        n_ok = sum(
            1
            for ln in lines
            if not re.search(r"\brevert\b|\bhotfix\b|\bfix\b", ln, re.I)
        )
        return n_tot, n_ok

    n_git_total, n_git_ok = git_commit_stats(needle)
    N_TOTAL = n_git_total if n_git_total > 0 else total
    N_SUCCESS = n_git_ok if n_git_total > 0 else successes
    if N_TOTAL < 3:
        conf = 0.4
    else:
        conf = round(N_SUCCESS / max(N_TOTAL, 1), 3)
        if N_TOTAL >= 10:
            conf = round(min(conf, 0.95), 3)

    risk_touch = [
        r
        for r in decisions
        if str(r.get("type", "")).lower() == "risk_acceptance"
        and needle.lower() in json.dumps(r, ensure_ascii=False).lower()
    ]

    learn_path = ROOT / ".claude" / "learning-log.md"
    learn_text = ""
    if learn_path.is_file():
        learn_text = learn_path.read_text(encoding="utf-8", errors="replace")

    failure_snippets = []
    phase_hits = []
    if learn_text:
        blocks = re.split(r"(?m)^###\s+", learn_text)
        for blk in blocks:
            if needle.lower() not in blk.lower():
                continue
            first = blk.splitlines()[0] if blk.splitlines() else ""
            if re.search(r"Falhou|Passou a regra|Evitar|avoid|failure", blk, re.I):
                phase_hits.append(f"### {first.strip()[:120]}\n" + "\n".join(blk.splitlines()[1:8]))
        for ln in learn_text.splitlines():
            low = ln.lower()
            if needle.lower() not in low and Path(needle).parent.as_posix().lower() not in low:
                continue
            if re.search(r"avoid|failure|incident|lesson|never|anti-pattern|revert", low):
                failure_snippets.append(ln.strip()[:240])

    heur_lines = []
    for hp in (
        ROOT / ".claude" / "heuristics" / "operational.md",
        ROOT / "heuristics" / "operational.md",
    ):
        if hp.is_file():
            for ln in hp.read_text(encoding="utf-8", errors="replace").splitlines():
                low = ln.lower()
                if needle.lower() in low or Path(needle).name.lower() in low:
                    heur_lines.append(ln.strip()[:220])
            if heur_lines:
                break

    inv_path = ROOT / ".claude" / "invariants.json"
    matched_invs = []
    if inv_path.is_file():
        try:
            data = json.loads(inv_path.read_text(encoding="utf-8", errors="replace"))
        except json.JSONDecodeError:
            data = {}
        for inv in data.get("invariants") or []:
            if isinstance(inv, dict) and inv_touches_module(inv, needle):
                matched_invs.append(inv)

    epi_facts = []
    epi_path = ROOT / ".claude" / "epistemic-state.json"
    if epi_path.is_file():
        try:
            ep = json.loads(epi_path.read_text(encoding="utf-8", errors="replace"))
        except json.JSONDecodeError:
            ep = {}
        facts = ep.get("facts") or {}
        if isinstance(facts, dict):
            for fk, meta in facts.items():
                if not isinstance(meta, dict):
                    continue
                st = str(meta.get("statement", ""))
                if needle.lower() in st.lower() or Path(needle).name.lower() in st.lower():
                    epi_facts.append((fk, meta))

    ts = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    session_ids = sorted(
        {str(r.get("session", "")) for r in decisions if r.get("session")}, key=str
    )[-12:]

    rb_dir = ROOT / ".claude" / "runbooks"
    rb_dir.mkdir(parents=True, exist_ok=True)
    out_md = rb_dir / f"{slug}.md"
    out_meta = rb_dir / f"{slug}.meta.json"

    lines = []
    lines.append(f"<!-- .claude/runbooks/{slug}.md — procedural consolidation (generated) -->")
    lines.append(f"<!-- module: {mod_raw} | generated_at: {ts} -->")
    lines.append(
        f"<!-- evidence: {total} decision rows (180d) | git_commits_180d: {n_git_total} ok_heuristic: {n_git_ok} | decision_success_signal: {successes} -->"
    )
    lines.append(
        f"<!-- confidence: {conf} | draft: {'yes' if N_TOTAL < 3 else 'no'} | risk_acceptance_rows: {len(risk_touch)} -->"
    )
    lines.append(f"<!-- sessions_sample: {', '.join(session_ids) or 'n/a'} -->")
    lines.append("")
    lines.append(f"# Runbook: safe change — `{mod_raw}`")
    lines.append("")
    lines.append("## Pre-conditions (verify before starting)")
    step = 0
    if not matched_invs:
        step += 1
        lines.append(
            f"{step}. Review `.claude/invariants.json` — no invariant scope matched this path; tighten scopes if this surface is critical."
        )
    for inv in matched_invs[:12]:
        step += 1
        iid = inv.get("id", "?")
        name = inv.get("name", "")
        sev = inv.get("violation_severity", "")
        lines.append(
            f"{step}. **{iid}** {name} ({sev}) — `bash .claude/scripts/invariant-engine.sh --verify {iid}`"
        )
    step += 1
    lines.append(
        f"{step}. **Coordination** — `bash .claude/scripts/agent-coordinator.sh --check {dir_guess}`"
    )
    step += 1
    lines.append(
        f"{step}. **Epistemic facts** — inspect `.claude/epistemic-state.json` for statements affecting this path."
    )
    for fk, meta in epi_facts[:5]:
        st = str(meta.get("statement", ""))[:160]
        lines.append(f"   - `{fk}`: {st}")
    lines.append("")

    lines.append("## Sequence (evidence-derived — validate before treating as law)")
    seq_n = 0
    if decisions:
        for r in reversed(decisions[-20:]):
            rid = r.get("id", "?")
            typ = r.get("type", "")
            dec = str(r.get("decision", ""))[:200].replace("\n", " ")
            seq_n += 1
            lines.append(f"{seq_n}. [{rid}] ({typ}) {dec}")
            if seq_n >= 8:
                break
    else:
        seq_n += 1
        lines.append(
            f"{seq_n}. No decision-log rows referenced this module yet — record decisions with `decision-audit.sh` as work proceeds."
        )
    seq_n += 1
    lines.append(
        f"{seq_n}. **Forward simulation** — `bash .claude/scripts/simulate-change.sh --target \"{mod_raw}\" --change \"…\"`"
    )
    seq_n += 1
    lines.append(
        f"{seq_n}. **Typecheck incrementally** — `npx tsc --noEmit` (or project equivalent) after each coherent sub-change on critical paths."
    )
    lines.append("")

    lines.append("## Learning-log phases (auto-excerpt)")
    if phase_hits:
        for ph in phase_hits[:4]:
            lines.append(ph[:1200])
            lines.append("")
    else:
        lines.append("- (no ### sections matched this module path)")
    lines.append("")

    lines.append("## Heuristic references (operational.md)")
    if heur_lines:
        for h in heur_lines[:10]:
            lines.append(f"- {h}")
    else:
        lines.append("- (no operational.md lines matched)")
    lines.append("")

    lines.append("## Known failure modes (from learning-log + decision heuristics)")
    if failure_snippets:
        for s in failure_snippets[:12]:
            lines.append(f"- {s}")
    else:
        lines.append(
            "- (none auto-linked — search `learning-log.md` manually for this path; add anti-patterns when you learn them)"
        )
    lines.append("")
    if any(not is_success_signal(r) for r in decisions[-8:]):
        lines.append(
            "- **Note:** recent decision rows matched *failure* heuristics (revert/incident language). Treat sequence above as *audit trail*, not proof of good procedure until reviewed."
        )
        lines.append("")

    lines.append("## Rollback")
    lines.append(
        "- Prefer small commits per sub-change; use `git revert <sha>` or `git restore -p` as appropriate for your branching model."
    )
    lines.append("")

    out_md.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    meta = {
        "slug": slug,
        "module": mod_raw,
        "generated_at": ts,
        "decision_rows_total": total,
        "decision_rows_success_heuristic": successes,
        "git_commits_180d_total": n_git_total,
        "git_commits_180d_ok_heuristic": n_git_ok,
        "N_TOTAL_effective": N_TOTAL,
        "N_SUCCESS_effective": N_SUCCESS,
        "confidence": conf,
        "invariants_matched": [i.get("id") for i in matched_invs],
        "runbook_path": str(out_md.relative_to(ROOT)).replace("\\", "/"),
    }
    out_meta.write_text(json.dumps(meta, indent=2), encoding="utf-8", newline="\n")

    print(f"[OS-RUNBOOK] consolidated → {out_md.relative_to(ROOT)}")
    print(f"  confidence (heuristic): {conf}  (success-like rows / total touching = {successes}/{max(total,1)})")
    print(f"  meta: {out_meta.relative_to(ROOT)}")


if __name__ == "__main__":
    try:
        main()
    except OSError as e:
        print(f"[OS-RUNBOOK] ERROR: {e}", file=__import__('sys').stderr)
PY

exit 0
