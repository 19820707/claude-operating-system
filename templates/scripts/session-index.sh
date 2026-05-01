#!/usr/bin/env bash
# Semantic session index — parses session-state.md → .claude/session-index.json. H10: LF-only; exit 0.
set -euo pipefail

if [[ "${1:-}" != "--query" ]]; then
  echo "[OS-SESSION-INDEX]"
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "  skip: python3 not available"
  exit 0
fi

mkdir -p .claude

python3 - "$@" <<'PY'
import json, re, subprocess, sys
from datetime import datetime, timezone
from pathlib import Path


def extract_section(md: str, *headings: str) -> str:
    for h in headings:
        i = md.find(h)
        if i == -1:
            continue
        rest = md[i + len(h) :].lstrip("\n")
        out = []
        for line in rest.splitlines():
            if line.startswith("## ") and h not in line:
                break
            out.append(line)
        return "\n".join(out)
    return ""


def git_branch() -> str:
    try:
        return subprocess.check_output(
            ["git", "branch", "--show-current"], text=True, stderr=subprocess.DEVNULL
        ).strip() or "unknown"
    except Exception:
        return "unknown"


def git_head_short() -> str:
    try:
        return subprocess.check_output(
            ["git", "log", "-1", "--format=%h"], text=True, stderr=subprocess.DEVNULL
        ).strip() or ""
    except Exception:
        return ""


def parse_phase(md: str) -> str:
    sec = extract_section(md, "## Fase actual", "## Current Phase")
    for line in sec.splitlines():
        t = line.strip()
        if not t or t == "---" or t.startswith("<!--"):
            continue
        if t.startswith("|"):
            continue
        if t.startswith("#"):
            continue
        return t
    return ""


def parse_table_branch_head(md: str) -> tuple[str, str]:
    ident = extract_section(md, "## Identificação")
    branch = ""
    head = ""
    for line in ident.splitlines():
        m = re.match(r"^\|\s*Branch\s*\|\s*`?([^`|]+)`?\s*\|", line, re.I)
        if m:
            branch = m.group(1).strip()
        m = re.match(r"^\|\s*HEAD\s*\|\s*`?([^`|]+)`?\s*\|", line, re.I)
        if m:
            head = m.group(1).strip().split()[0]
    return branch, head


def parse_modules(md: str) -> list[str]:
    sec = extract_section(md, "## Estado implementado", "## Implemented state")
    mods = []
    for line in sec.splitlines():
        for m in re.finditer(r"(?:server|client)/[\w./@-]+", line):
            mods.append(m.group(0))
    return sorted(set(mods))


def parse_decisions(md: str) -> list[dict]:
    sec = extract_section(md, "## Decisões tomadas", "## Decisions taken")
    rows = []
    for line in sec.splitlines():
        line = line.rstrip()
        if "|" not in line or re.match(r"^\|\s*-+", line):
            continue
        parts = [p.strip() for p in line.split("|")]
        if len(parts) < 3:
            continue
        if parts[1].lower() in ("id", "----"):
            continue
        did = parts[1]
        if not re.match(r"D-\d+", did):
            continue
        rows.append(
            {
                "id": did,
                "text": parts[2] if len(parts) > 2 else "",
                "files": parts[3] if len(parts) > 3 else "",
                "commit": parts[4].split()[0] if len(parts) > 4 else "",
                "risk": parts[5] if len(parts) > 5 else "",
            }
        )
    return rows


def parse_risks(md: str) -> list[str]:
    sec = extract_section(md, "## Riscos abertos", "## Open risks")
    risks = []
    for line in sec.splitlines():
        if "|" not in line or re.match(r"^\|\s*-+", line):
            continue
        parts = [p.strip() for p in line.split("|")]
        if len(parts) < 3:
            continue
        if parts[1].lower() in ("risco", "risk", "----"):
            continue
        if parts[1]:
            risks.append(parts[1])
    return risks


def parse_heuristics(md: str) -> list[str]:
    return sorted(set(re.findall(r"H\d+", md)))


def load_index(path: Path) -> dict:
    if path.is_file():
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            pass
    return {
        "schemaVersion": 1,
        "sessions": [],
        "open_risks": [],
        "decisions_by_module": {},
    }


def query(idx: dict, module: str):
    dbm = idx.get("decisions_by_module") or {}
    print(f"[OS-SESSION-INDEX] decisions for {module}:")
    seen = False
    for rec in dbm.get(module, []):
        seen = True
        cid = rec.get("id", "?")
        txt = rec.get("text", "")
        when = rec.get("session_id", "")
        commit = rec.get("commit", "")
        print(f"  {cid} — {txt} ({when}, commit {commit})")
    if not seen:
        print("  (none recorded)")
    risks = idx.get("open_risks") or []
    if isinstance(risks, list) and risks:
        texts = []
        for r in risks:
            if isinstance(r, dict):
                texts.append(str(r.get("text", r)))
            else:
                texts.append(str(r))
        texts = [t for t in texts if t]
        if texts:
            print(f"  open risks: {', '.join(texts)}")


def main():
    args = sys.argv[1:]
    out_path = Path(".claude/session-index.json")
    state_path = Path(".claude/session-state.md")

    if args and args[0] == "--query" and len(args) > 1:
        idx = load_index(out_path)
        query(idx, args[1])
        return

    if not state_path.is_file():
        print("  skip: no .claude/session-state.md")
        return

    md = state_path.read_text(encoding="utf-8", errors="replace")
    phase = parse_phase(md)
    branch, head = parse_table_branch_head(md)
    if not head:
        head = git_head_short()
    if not branch:
        branch = git_branch()
    modules = parse_modules(md)
    decisions = parse_decisions(md)
    risks_opened = parse_risks(md)
    heuristics = parse_heuristics(md)

    day = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    sid = f"{day}-{branch.replace('/', '-')}"

    idx = load_index(out_path)
    prev_open = idx.get("open_risks") or []
    prev_texts = set()
    for r in prev_open:
        if isinstance(r, dict):
            prev_texts.add(r.get("text", ""))
        else:
            prev_texts.add(str(r))
    new_texts = set(risks_opened)
    closed = [t for t in prev_texts if t and t not in new_texts]

    entry = {
        "id": sid,
        "phase": phase,
        "head": head,
        "branch": branch,
        "modules_touched": modules,
        "decisions": decisions,
        "risks_opened": risks_opened,
        "risks_closed": closed,
        "heuristics_applied": heuristics,
        "indexed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }

    sessions = [s for s in idx.get("sessions", []) if s.get("id") != sid]
    sessions.append(entry)
    idx["sessions"] = sessions[-200:]

    or_list = []
    for t in risks_opened:
        if t:
            or_list.append({"text": t, "session_id": sid})
    idx["open_risks"] = or_list

    dbm = idx.get("decisions_by_module") or {}
    for mod in modules:
        lst = dbm.setdefault(mod, [])
        for d in decisions:
            rec = {
                "id": d["id"],
                "text": d.get("text", ""),
                "commit": d.get("commit", ""),
                "session_id": sid,
            }
            if not any(
                x.get("id") == rec["id"] and x.get("session_id") == sid for x in lst
            ):
                lst.append(rec)
        dbm[mod] = lst[-50:]
    idx["decisions_by_module"] = dbm
    idx["updated"] = entry["indexed_at"]

    out_path.write_text(json.dumps(idx, indent=2), encoding="utf-8")
    print(f"  ok: wrote {out_path} session={sid} decisions={len(decisions)} modules={len(modules)}")


if __name__ == "__main__":
    main()
PY

exit 0
