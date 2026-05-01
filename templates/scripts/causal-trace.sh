#!/usr/bin/env bash
# Causal chain trace — file / commit / incident vs session-index.json. H10: LF-only; exit 0.
set -euo pipefail

echo "[OS-CAUSAL-TRACE]"

if ! command -v python3 >/dev/null 2>&1; then
  echo "  skip: python3 not available"
  exit 0
fi

python3 - "$@" <<'PY'
import json, re, subprocess, sys
from pathlib import Path


def load_index() -> dict:
    p = Path(".claude/session-index.json")
    if not p.is_file():
        return {}
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return {}


def git_text(cmd: list[str]) -> str:
    try:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        return ""


def decisions_for_commit_hash(idx: dict, short7: str) -> list[dict]:
    out = []
    s = short7.strip()[:7]
    seen = set()
    for sess in idx.get("sessions", []):
        for d in sess.get("decisions", []) or []:
            c = (d.get("commit") or "").strip()
            if not c:
                continue
            cp = c[:7]
            if cp == s or c.startswith(s) or s.startswith(cp):
                key = (d.get("id"), cp)
                if key in seen:
                    continue
                seen.add(key)
                out.append({**d, "_session": sess.get("id", "")})
    return out


def commit_date_for_file(rev: str, filepath: str) -> str:
    d = git_text(
        ["git", "log", "-1", "--format=%ad", "--date=short", rev, "--", filepath]
    ).strip()
    return d or "????-??-??"


def mode_file(filepath: str):
    idx = load_index()
    log = git_text(
        ["git", "log", "-n", "20", "--oneline", "--follow", "--", filepath]
    )
    print(f"  file: {filepath}")
    if not log.strip():
        print("  (no git history for this path)")
        return
    for line in log.splitlines():
        line = line.strip()
        if not line:
            continue
        h, _, msg = line.partition(" ")
        h = h.strip()
        msg = msg.strip()
        if not h:
            continue
        dday = commit_date_for_file(h, filepath)
        rel = decisions_for_commit_hash(idx, h[:7])
        print(f"  ── {dday} {h} {msg}")
        if rel:
            d = rel[-1]
            print(f"     decision: {d.get('id')} — {d.get('text') or ''}")
            print(f"     risk accepted: {d.get('risk') or 'unknown'}")
        else:
            print("     unknown decision (undocumented change)")


def mode_commit(commit: str):
    idx = load_index()
    short = commit[:7]
    stat = git_text(["git", "show", "--stat", "--oneline", commit])
    if stat.strip():
        print("  git show --stat:")
        for ln in stat.splitlines()[:30]:
            print(f"    {ln}")
        if len(stat.splitlines()) > 30:
            print("    ...")
    head = git_text(
        ["git", "show", "-s", "--format=%h %ci %s", commit]
    ).strip()
    print(f"  commit: {commit}")
    if head:
        print(f"  {head}")
    files = git_text(
        ["git", "diff-tree", "--no-commit-id", "--name-only", "-r", commit]
    )
    paths = [f.strip() for f in files.splitlines() if f.strip()]
    decs = decisions_for_commit_hash(idx, short)
    for fp in paths[:40]:
        print(f"  file: {fp}")
        hit = None
        for d in decs:
            files_col = d.get("files") or ""
            if not files_col or fp in files_col or files_col in fp:
                hit = d
                break
        if not hit and decs:
            hit = decs[-1]
        if hit:
            print(f"    decision: {hit.get('id')} — {hit.get('text')}")
            print(f"    risk accepted: {hit.get('risk') or 'unknown'}")
        else:
            print("    unknown decision (undocumented change)")


def mode_incident():
    idx = load_index()
    st = Path(".claude/session-state.md")
    if not st.is_file():
        print("  skip: no session-state.md")
        return
    md = st.read_text(encoding="utf-8", errors="replace")
    sec = ""
    for tag in ("## Riscos abertos", "## Open risks"):
        if tag in md:
            i = md.find(tag)
            rest = md[i + len(tag) :]
            for line in rest.splitlines():
                if line.startswith("## ") and not line.startswith(tag):
                    break
                sec += line + "\n"
            break
    risks = []
    for line in sec.splitlines():
        if "|" not in line or re.match(r"^\|\s*-+", line):
            continue
        parts = [p.strip() for p in line.split("|")]
        if len(parts) > 2 and parts[1] and parts[1].lower() not in ("risco", "risk", "severity"):
            risks.append(parts[1])
    print("  incident / open-risk trace:")
    for r in risks:
        if not r:
            continue
        print(f"  risk: {r}")
        found = False
        for sess in reversed(idx.get("sessions", [])):
            for d in sess.get("decisions", []) or []:
                t = (d.get("text") or "") + " " + (d.get("files") or "")
                if r.lower() in t.lower():
                    print(f"    → decision: {d.get('id')} — {d.get('text')}")
                    print(f"    → commit: {d.get('commit')}  files: {d.get('files')}")
                    print(f"    → risk accepted then: {d.get('risk') or 'unknown'}")
                    found = True
                    break
            if found:
                break
        if not found:
            print("    → no matching decision in session-index (undocumented)")


def main():
    a = sys.argv[1:]
    if not a:
        print("  usage: causal-trace.sh --file <path> | --commit <hash> | --incident")
        return
    if a[0] == "--file" and len(a) > 1:
        mode_file(a[1])
    elif a[0] == "--commit" and len(a) > 1:
        mode_commit(a[1])
    elif a[0] == "--incident":
        mode_incident()
    else:
        print("  usage: causal-trace.sh --file <path> | --commit <hash> | --incident")


if __name__ == "__main__":
    main()
PY

exit 0
