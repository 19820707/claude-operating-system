#!/usr/bin/env bash
# Context topology — merge knowledge graph + subgraph injection + token budget heuristic. H10: LF-only; exit 0.
set -euo pipefail

echo "[OS-CONTEXT-TOPOLOGY]"

if ! command -v python3 >/dev/null 2>&1; then
  echo "  skip: python3 not available"
  exit 0
fi

python3 - "$@" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO = Path.cwd()
KG = REPO / ".claude" / "knowledge-graph.json"
ARCH = REPO / ".claude" / "architecture-graph.json"
COMP = REPO / ".claude" / "complexity-map.json"
STATE = REPO / ".claude" / "session-state.md"
POL = REPO / ".claude" / "policies"


def load_json(p: Path, default):
    if not p.is_file():
        return default
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return default


def file_to_module(rel: str) -> str:
    rel = rel.replace("\\", "/").strip("/")
    parts = rel.split("/")
    if len(parts) >= 2 and parts[0] in ("server", "client", "shared"):
        return f"{parts[0]}/{parts[1]}"
    if parts[0] == "src" and len(parts) >= 2:
        return f"src/{parts[1]}"
    return parts[0] if parts else "."


def refresh_graph():
    arch = load_json(ARCH, {})
    comp = load_json(COMP, {})
    kg = load_json(
        KG,
        {
            "schemaVersion": 1,
            "updated": "",
            "nodes": {},
            "edges": [],
            "invariants": [],
            "open_questions": [],
        },
    )
    nodes = kg.setdefault("nodes", {})
    for n in arch.get("nodes") or []:
        mid = n.get("id")
        if not mid:
            continue
        nodes[mid] = {
            "type": "module",
            "contracts": {
                "exports": [],
                "invariants": [],
                "implicit_dependencies": [],
            },
            "risk_profile": {
                "level": n.get("criticality", "UNKNOWN"),
                "stability": n.get("stability"),
                "churn_90d": n.get("churn_90d_commits"),
            },
        }
    for row in comp.get("files") or []:
        fp = (row.get("path") or "").replace("\\", "/")
        if not fp:
            continue
        mod = file_to_module(fp)
        if mod not in nodes:
            nodes[mod] = {
                "type": "module",
                "contracts": {"exports": [], "invariants": [], "implicit_dependencies": []},
                "risk_profile": {},
            }
        entry = nodes.setdefault(fp, {"type": "file", "module": mod, "risk_profile": {}})
        entry["risk_profile"] = {
            "score": row.get("score"),
            "level": row.get("level"),
            "churn": row.get("churn"),
        }
    edges = []
    for e in arch.get("module_edges") or []:
        if isinstance(e, dict) and e.get("from") and e.get("to"):
            edges.append(
                {
                    "from": e["from"],
                    "to": e["to"],
                    "type": "import_dependency",
                    "import_count": e.get("import_count", 1),
                }
            )
    kg["edges"] = edges[:2000]
    kg["updated"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    KG.parent.mkdir(parents=True, exist_ok=True)
    KG.write_text(json.dumps(kg, indent=2), encoding="utf-8")
    print(f"  refreshed {KG.as_posix()} ({len(nodes)} nodes, {len(edges)} edges)")


def subgraph_for(target: str):
    if not KG.is_file():
        refresh_graph()
    kg = load_json(KG, {})
    nodes = kg.get("nodes") or {}
    edges = kg.get("edges") or []
    mod = file_to_module(target)
    keep = {mod, target}
    for e in edges:
        if e.get("to") == mod or e.get("from") == mod:
            keep.add(str(e.get("from")))
            keep.add(str(e.get("to")))
    print("INJECTION (relevant subgraph — paste into session or command context):")
    print(f"  focus: {target} (module `{mod}`)")
    for k in sorted(keep):
        if k in nodes:
            n = nodes[k]
            print(f"  - {k}: {json.dumps(n, ensure_ascii=False)[:400]}")
    print("  (truncate in real use; regenerate with context-topology.sh --refresh)")


def char_tokens(n: int) -> int:
    return max(1, n // 4)


def budget_for(target: str | None):
    avail = 180_000
    code_chars = 0
    if target:
        rel = target.replace("\\", "/")
        p = REPO / rel
        if p.is_file():
            code_chars += len(p.read_text(encoding="utf-8", errors="replace"))
            parent = p.parent
            n = 0
            for ch in list(parent.glob("*.ts")) + list(parent.glob("*.tsx")):
                if n >= 14:
                    break
                try:
                    code_chars += len(ch.read_text(encoding="utf-8", errors="replace"))
                except OSError:
                    pass
                n += 1
    pol_chars = 0
    if POL.is_dir():
        for f in POL.glob("*.md"):
            try:
                pol_chars += len(f.read_text(encoding="utf-8", errors="replace"))
            except OSError:
                pass
    kg = load_json(KG, {})
    nn = len(kg.get("nodes") or {})
    kg_chars = min(40_000, 2000 + nn * 120) if nn else 2000
    sess_chars = len(STATE.read_text(encoding="utf-8", errors="replace")) if STATE.is_file() else 0
    subgraph = char_tokens(min(kg_chars * 8, 32_000))
    code_t = char_tokens(code_chars) if code_chars else 12_000
    pol_t = char_tokens(min(pol_chars, 80_000))
    sess_t = char_tokens(sess_chars) if sess_chars else 3000
    used = code_t + subgraph + pol_t + sess_t
    op = avail - used
    print("session context allocation (heuristic tokens ≈ chars/4):")
    print(f"  available tokens (budget): ~{avail:,}")
    print(f"  code to read (target + module dir proxy): ~{code_t:,}")
    print(f"  knowledge graph (relevant slice estimate): ~{subgraph:,}")
    print(f"  policies (.claude/policies/*.md, capped): ~{pol_t:,}")
    print(f"  session continuity (session-state.md): ~{sess_t:,}")
    print(f"  operational budget (remaining): ~{op:,}")
    if used > 140_000:
        print("  WARNING: estimated footprint > 140,000 — trigger pre-compact / narrow read set")
    if target:
        print(f"  INJECTION: attach subgraph for `{target}` (run with --inject {target})")


def main():
    args = sys.argv[1:]
    if not args or "--refresh" in args:
        refresh_graph()
    if "--inject" in args:
        i = args.index("--inject")
        tgt = args[i + 1] if i + 1 < len(args) else ""
        if tgt:
            subgraph_for(tgt.replace("\\", "/"))
    if "--budget" in args:
        tgt = None
        if "--for" in args:
            j = args.index("--for")
            tgt = args[j + 1] if j + 1 < len(args) else None
        budget_for(tgt)


if __name__ == "__main__":
    main()
PY

exit 0
