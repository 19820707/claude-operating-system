#!/usr/bin/env bash
# Cross-project learning sync — contribute / inherit / report vs OS repo evidence file. H10: LF-only; exit 0.
set -euo pipefail

echo "[OS-CROSS-PROJECT-SYNC]"

if ! command -v python3 >/dev/null 2>&1; then
  echo "  skip: python3 not available"
  exit 0
fi

python3 - "$@" <<'PY'
import json, re, subprocess, sys
from datetime import date, datetime, timezone
from pathlib import Path


def project_name() -> str:
    try:
        root = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"], text=True, stderr=subprocess.DEVNULL
        ).strip()
        return Path(root).name
    except Exception:
        return Path.cwd().name


def load_json(p: Path) -> dict:
    if not p.is_file():
        return {"updated": "", "patterns": {}}
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return {"updated": "", "patterns": {}}


def slugify_pattern(name: str) -> str:
    s = re.sub(r"[^\w\-]+", "-", name.lower()).strip("-")
    return s[:80] or "pattern"


def extract_pattern_blocks(md: str) -> list[dict]:
    """Front-matter-like blocks containing pattern: (--- delimited)."""
    out = []
    i = 0
    while True:
        a = md.find("---", i)
        if a == -1:
            break
        b = md.find("---", a + 3)
        if b == -1:
            break
        blk = md[a + 3 : b].strip()
        if "pattern:" in blk.lower():
            kv = {}
            for line in blk.splitlines():
                if ":" not in line or line.strip().startswith("#"):
                    continue
                k, _, v = line.partition(":")
                key = k.strip().lower()
                kv[key] = v.strip()
            pat = kv.get("pattern", "").strip()
            if pat:
                out.append({"slug": slugify_pattern(pat), "raw": kv})
        i = b + 3
    return out


def cmd_contribute(os_repo: str):
    ll = Path(".claude/learning-log.md")
    if not ll.is_file():
        print("  skip: no .claude/learning-log.md")
        return
    root = Path(os_repo)
    if not root.is_dir():
        print(f"  skip: OS repo not found: {os_repo}")
        return
    ev_path = root / "heuristics" / "cross-project-evidence.json"
    md = ll.read_text(encoding="utf-8", errors="replace")
    blocks = extract_pattern_blocks(md)
    data = load_json(ev_path)
    patterns = data.setdefault("patterns", {})
    proj = project_name()
    today = date.today().isoformat()
    n = 0
    for b in blocks:
        slug = b["slug"]
        raw = b["raw"]
        try:
            conf = int(raw.get("confirmed", "1") or 1)
        except ValueError:
            conf = 1
        entry = patterns.get(slug)
        if not entry:
            entry = {
                "confirmed_in": [],
                "total_confirmations": 0,
                "last_seen": today,
                "promoted_to": None,
                "impact": raw.get("evidence", "")[:200],
            }
            patterns[slug] = entry
        if proj not in entry["confirmed_in"]:
            entry["confirmed_in"].append(proj)
        entry["total_confirmations"] = int(entry.get("total_confirmations", 0)) + conf
        entry["last_seen"] = today
        heur = raw.get("heuristic")
        if heur and re.match(r"H\d+", heur):
            entry["promoted_to"] = heur
        if raw.get("evidence"):
            entry["impact"] = raw.get("evidence", "")[:200]
        n += 1
    data["updated"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    ev_path.parent.mkdir(parents=True, exist_ok=True)
    ev_path.write_text(json.dumps(data, indent=2), encoding="utf-8")
    print(f"  CONTRIBUTED: {n} pattern block(s) from {proj} to {ev_path}")


def cmd_inherit(os_repo: str):
    root = Path(os_repo)
    if not root.is_dir():
        print(f"  skip: OS repo not found: {os_repo}")
        return
    ev_path = root / "heuristics" / "cross-project-evidence.json"
    data = load_json(ev_path)
    patterns = data.get("patterns") or {}
    ll = Path(".claude/learning-log.md")
    if not ll.is_file():
        print("  skip: no .claude/learning-log.md")
        return
    body = ll.read_text(encoding="utf-8", errors="replace")
    added = 0
    for slug, meta in patterns.items():
        try:
            tc = int(meta.get("total_confirmations", 0))
        except Exception:
            tc = 0
        if tc < 2:
            continue
        marker = f"### Inherited — {slug} (cross-project"
        if marker in body:
            continue
        cin = meta.get("confirmed_in") or []
        projects = ", ".join(cin) if isinstance(cin, list) else str(cin)
        impact = meta.get("impact", "")
        block = f"""

### Inherited — {slug} (cross-project, {tc} confirmations)
**Source:** confirmed in: {projects}
**Impact:** {impact}
**Status:** inherited — validate in this project

"""
        body = body.rstrip() + "\n" + block
        added += 1
    if added:
        ll.write_text(body, encoding="utf-8")
    print(f"  INHERITED: {added} pattern(s) from cross-project knowledge")


def cmd_report(os_repo: str):
    root = Path(os_repo)
    if not root.is_dir():
        print(f"  skip: OS repo not found: {os_repo}")
        return
    ev_path = root / "heuristics" / "cross-project-evidence.json"
    data = load_json(ev_path)
    print(f"  report: {ev_path}")
    print(f"  updated: {data.get('updated', '')}")
    for slug, meta in sorted((data.get("patterns") or {}).items()):
        tc = meta.get("total_confirmations", 0)
        cin = meta.get("confirmed_in", [])
        pr = meta.get("promoted_to")
        print(f"    - {slug}: confirmations={tc} promoted={pr} projects={cin}")


def main():
    a = sys.argv[1:]
    if len(a) < 2:
        print("  usage: cross-project-sync.sh --contribute <os-repo-path>")
        print("         cross-project-sync.sh --inherit <os-repo-path>")
        print("         cross-project-sync.sh --report <os-repo-path>")
        return
    mode, path = a[0], a[1]
    if mode == "--contribute":
        cmd_contribute(path)
    elif mode == "--inherit":
        cmd_inherit(path)
    elif mode == "--report":
        cmd_report(path)
    else:
        print("  unknown mode")


if __name__ == "__main__":
    main()
PY

exit 0
