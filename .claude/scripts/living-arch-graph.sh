#!/usr/bin/env bash
# Living architecture graph — import graph from code, blast radius, boundary violations. H10: LF-only; exit 0.
set -euo pipefail

echo "[OS-LIVING-ARCH]"

if ! command -v python3 >/dev/null 2>&1; then
  echo "  skip: python3 not available"
  exit 0
fi

python3 - "$@" <<'PY'
import json
import os
import re
import subprocess
import sys
from collections import defaultdict, deque
from datetime import datetime, timezone
from pathlib import Path

SKIP_DIRS = {
    ".git",
    "node_modules",
    "dist",
    "build",
    ".next",
    "coverage",
    ".turbo",
    "vendor",
    ".local",
    ".claude",
}
CODE_EXT = {".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".mts", ".cts"}
ROOT = Path.cwd().resolve()

RE_IMPORTS = [
    re.compile(r"""from\s+['"]([^'"]+)['"]"""),
    re.compile(r"""import\s*\(\s*['"]([^'"]+)['"]\s*\)"""),
    re.compile(r"""require\s*\(\s*['"]([^'"]+)['"]\s*\)"""),
]


def should_skip_dir(name: str) -> bool:
    return name in SKIP_DIRS or name.startswith(".")


def code_roots() -> list[Path]:
    roots = []
    for name in ("server", "client", "shared", "src"):
        p = ROOT / name
        if p.is_dir():
            roots.append(p)
    return roots


def iter_code_files() -> list[Path]:
    out: list[Path] = []
    for base in code_roots():
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames if not should_skip_dir(d)]
            for fn in filenames:
                if Path(fn).suffix not in CODE_EXT:
                    continue
                fp = Path(dirpath) / fn
                out.append(fp.resolve())
    return sorted(set(out))


def file_to_module(rel_posix: str) -> str:
    rel_posix = rel_posix.replace("\\", "/").strip("/")
    parts = rel_posix.split("/")
    if len(parts) >= 2 and parts[0] in ("server", "client", "shared"):
        return f"{parts[0]}/{parts[1]}"
    if parts[0] == "src" and len(parts) >= 2:
        return f"src/{parts[1]}"
    if parts:
        return parts[0]
    return "."


def resolve_internal(spec: str, src_file: Path) -> str | None:
    if not spec.startswith("."):
        return None
    if spec.startswith(("http://", "https://", "node:")):
        return None
    try:
        tgt = (src_file.parent / spec).resolve()
        rel = tgt.relative_to(ROOT)
    except Exception:
        return None
    s = rel.as_posix()
    direct = ROOT / s
    if direct.is_file():
        return s
    stem = ROOT / s
    if stem.suffix not in CODE_EXT:
        for suf in (".ts", ".tsx", ".mts", ".cts", ".js", ".jsx"):
            c = stem.with_suffix(suf)
            if c.is_file():
                return c.relative_to(ROOT).as_posix()
        for idx in ("index.ts", "index.tsx", "index.js", "index.jsx"):
            c = stem / idx
            if c.is_file():
                return c.relative_to(ROOT).as_posix()
    return None


def parse_imports(text: str) -> list[str]:
    found: list[str] = []
    for rx in RE_IMPORTS:
        found.extend(m.group(1) for m in rx.finditer(text))
    return found


def load_json(path: Path, default):
    if not path.is_file():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def load_boundaries() -> dict:
    p = ROOT / ".claude" / "architecture-boundaries.json"
    data = load_json(p, {})
    pairs = data.get("forbidden_pairs") or []
    out = []
    for item in pairs:
        if isinstance(item, dict) and item.get("from_prefix") and item.get("to_prefix"):
            out.append(
                {
                    "from_prefix": str(item["from_prefix"]),
                    "to_prefix": str(item["to_prefix"]),
                    "reason": str(item.get("reason", "architectural boundary")),
                }
            )
    if not out:
        out = [
            {
                "from_prefix": "server/",
                "to_prefix": "client/",
                "reason": "server must not import client UI",
            }
        ]
    return {"forbidden_pairs": out}


def violates_boundary(from_file: str, to_file: str, rules: list[dict]) -> str | None:
    ff = from_file.replace("\\", "/")
    tf = to_file.replace("\\", "/")
    for r in rules:
        if ff.startswith(r["from_prefix"]) and tf.startswith(r["to_prefix"]):
            return r["reason"]
    return None


def git_lines_since(module_prefix: str, days: int = 90) -> int:
    spec = module_prefix.rstrip("/") + "/"
    if not (ROOT / spec.split("/")[0]).exists():
        return 0
    try:
        out = subprocess.check_output(
            [
                "git",
                "log",
                "--since",
                f"{days} days ago",
                "--oneline",
                "--",
                spec,
            ],
            cwd=str(ROOT),
            text=True,
            stderr=subprocess.DEVNULL,
        )
        return len([l for l in out.splitlines() if l.strip()])
    except Exception:
        return 0


def build_graph(files: list[Path]) -> tuple[dict[str, list[str]], list[tuple[str, str]]]:
    """forward: importer -> [imported]"""
    fwd: dict[str, list[str]] = defaultdict(list)
    edges: list[tuple[str, str]] = []
    rel_files = {f.relative_to(ROOT).as_posix() for f in files}
    for fp in files:
        rel = fp.relative_to(ROOT).as_posix()
        try:
            text = fp.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for spec in parse_imports(text):
            tgt = resolve_internal(spec, fp)
            if not tgt or tgt not in rel_files:
                continue
            if tgt == rel:
                continue
            fwd[rel].append(tgt)
            edges.append((rel, tgt))
    return fwd, edges


def reverse_graph(fwd: dict[str, list[str]]) -> dict[str, list[str]]:
    rev: dict[str, list[str]] = defaultdict(list)
    for a, bs in fwd.items():
        for b in bs:
            rev[b].append(a)
    return rev


def blast_radius(target_rel: str, rev: dict[str, list[str]], rel_files: set[str]) -> tuple[set[str], set[str], list[str]]:
    """Returns (direct_files, all_files, module_chain_bfs)."""
    if target_rel not in rel_files:
        return set(), set(), []
    direct = set(rev.get(target_rel, []))
    seen_files: set[str] = set()
    q = deque([target_rel])
    seen_files.add(target_rel)
    order_mods: list[str] = []
    while q:
        f = q.popleft()
        m = file_to_module(f)
        if not order_mods or order_mods[-1] != m:
            order_mods.append(m)
        for g in rev.get(f, []):
            if g not in seen_files:
                seen_files.add(g)
                q.append(g)
    affected = {x for x in seen_files if x != target_rel}
    return direct, affected, order_mods


def count_test_lines_for_modules(mods: set[str]) -> int:
    total = 0
    test_pat = re.compile(r"(\.(test|spec)\.(tsx?|jsx?)$)|/__tests__/|/tests?/", re.I)
    for base in code_roots():
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames if not should_skip_dir(d)]
            for fn in filenames:
                if Path(fn).suffix not in CODE_EXT:
                    continue
                rel = Path(dirpath, fn).resolve().relative_to(ROOT).as_posix()
                if not test_pat.search(rel):
                    continue
                mod = file_to_module(rel)
                if mod in mods or any(rel.startswith(m + "/") for m in mods):
                    try:
                        total += len(
                            Path(dirpath, fn).read_text(encoding="utf-8", errors="replace").splitlines()
                        )
                    except OSError:
                        pass
    return total


def order_idx(lvl: str) -> int:
    return {"LOW": 0, "MODERATE": 1, "ELEVATED": 2, "CRITICAL": 3}.get(lvl, 0)


def criticality_for_module(mod: str, cmap: dict) -> str:
    best = "LOW"
    order = {"LOW": 0, "MODERATE": 1, "ELEVATED": 2, "CRITICAL": 3}
    modn = mod.replace("\\", "/")
    prefix = modn.rstrip("/") + "/"
    for row in cmap.get("files") or []:
        p = (row.get("path") or "").replace("\\", "/")
        if p == modn or p.startswith(prefix):
            lvl = row.get("level") or "LOW"
            if order.get(lvl, 0) > order.get(best, 0):
                best = lvl
    return best


def cmd_blast_radius(target: str, fwd, rev, rel_files, cmap: dict, rules: list[dict]):
    t = target.replace("\\", "/").strip()
    if t not in rel_files:
        # try resolve as path
        cand = (ROOT / t).resolve()
        try:
            t = cand.relative_to(ROOT).as_posix()
        except Exception:
            print(f"  unknown file (not in scanned graph): {target}")
            print("  hint: run without args to build graph; file must live under server/, client/, shared/, or src/")
            return
    direct, affected, chain = blast_radius(t, rev, rel_files)
    direct_mods = {file_to_module(f) for f in direct}
    all_mods = {file_to_module(f) for f in affected} | {file_to_module(t)}
    trans_mods = all_mods - {file_to_module(t)}
    test_lines = count_test_lines_for_modules(all_mods)
    crit_chain = " → ".join(chain[:10]) if chain else file_to_module(t)
    max_crit = "LOW"
    for m in all_mods:
        c = criticality_for_module(m, cmap)
        if order_idx(c) > order_idx(max_crit):
            max_crit = c

    print(f"  proposal: change `{t}`")
    print("  blast radius:")
    print(f"    direct dependents (modules): {len(direct_mods)}")
    print(f"    transitive dependents (modules): {len(trans_mods)}")
    print(f"    critical path (module BFS order): {crit_chain}")
    print(f"    estimated test surface (lines in tests under affected modules): {test_lines}")
    rec = "Build — standard model selection"
    mode = "Build"
    if len(trans_mods) >= 15 or max_crit == "CRITICAL":
        rec = "Review mode — Opus mandatory"
        mode = "Review / Critical"
    elif len(trans_mods) >= 8 or max_crit in ("ELEVATED", "CRITICAL"):
        rec = "Review mode — Opus recommended for non-trivial edits"
        mode = "Review"
    print(f"    recommendation: {rec}")
    print(f"    mode hint: {mode}")


def main():
    args = sys.argv[1:]
    files = iter_code_files()
    if not files:
        print("  skip: no code files under server/, client/, shared/, or src/")
        Path(".claude").mkdir(parents=True, exist_ok=True)
        Path(".claude/architecture-graph.json").write_text(
            json.dumps(
                {
                    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "note": "empty graph — add server/, client/, shared/, or src/ tree",
                    "nodes": [],
                    "module_edges": [],
                    "violations": [],
                },
                indent=2,
            ),
            encoding="utf-8",
        )
        if args and args[0] == "--blast-radius":
            print("  cannot compute blast radius: no scanned code under roots")
        return

    fwd, file_edges = build_graph(files)
    rel_files = {f.relative_to(ROOT).as_posix() for f in files}
    rev = reverse_graph(fwd)
    bounds = load_boundaries()
    rules = bounds["forbidden_pairs"]

    violations = []
    for fr, to in file_edges:
        r = violates_boundary(fr, to, rules)
        if r:
            violations.append(
                {
                    "from_file": fr,
                    "to_file": to,
                    "from_module": file_to_module(fr),
                    "to_module": file_to_module(to),
                    "rule": r,
                }
            )

    mod_edge_count: dict[tuple[str, str], int] = defaultdict(int)
    for fr, to in file_edges:
        a, b = file_to_module(fr), file_to_module(to)
        if a != b:
            mod_edge_count[(a, b)] += 1

    cmap = load_json(ROOT / ".claude" / "complexity-map.json", {})

    nodes = []
    all_mods = {file_to_module(f.relative_to(ROOT).as_posix()) for f in files}
    for mod in sorted(all_mods):
        churn = git_lines_since(mod, 90)
        stability = round(1.0 / (1.0 + churn), 4) if churn >= 0 else 1.0
        bv = sum(1 for v in violations if v["from_module"] == mod)
        nodes.append(
            {
                "id": mod,
                "criticality": criticality_for_module(mod, cmap),
                "stability": stability,
                "churn_90d_commits": churn,
                "test_coverage": None,
                "boundary_violations": bv,
            }
        )

    module_edges = [
        {"from": a, "to": b, "import_count": c}
        for (a, b), c in sorted(mod_edge_count.items(), key=lambda x: -x[1])
    ]

    out = {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "schemaVersion": 1,
        "roots_scanned": [str(r.relative_to(ROOT).as_posix()) for r in code_roots()],
        "file_count": len(files),
        "file_edge_count": len(file_edges),
        "nodes": nodes,
        "module_edges": module_edges[:500],
        "violations": violations[:200],
    }

    Path(".claude").mkdir(parents=True, exist_ok=True)
    out_path = ROOT / ".claude" / "architecture-graph.json"
    out_path.write_text(json.dumps(out, indent=2), encoding="utf-8")
    print(f"  wrote {out_path} ({len(nodes)} modules, {len(file_edges)} file edges)")

    blast_only = bool(args and args[0] == "--blast-radius" and len(args) > 1)
    if violations and (not blast_only or "--violations" in args):
        for v in violations[:12]:
            print(
                "  BOUNDARY VIOLATION:",
                f"{v['from_module']} imports {v['to_module']} ({v['from_file']} -> {v['to_file']})",
            )
            print(f"    rule: {v['rule']}")
            print(
                "    ACTION: architectural decision required before merging this edge"
            )
    elif args and args[0] == "--violations" and not violations:
        print("  no boundary violations detected")

    if args and args[0] == "--blast-radius" and len(args) > 1:
        cmd_blast_radius(args[1], fwd, rev, rel_files, cmap, rules)
    elif args and args[0] not in ("--violations",):
        print(
            "  usage: living-arch-graph.sh | living-arch-graph.sh --blast-radius <path> | living-arch-graph.sh --violations"
        )


if __name__ == "__main__":
    main()
PY

exit 0
