#!/usr/bin/env bash
# Temporal consistency engine — staleness vs git, obsolescence heuristics, genealogy hints.
# Registry: .claude/invariants.json (object keyed by INV-*). H10: LF-only; exit 0.
set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

echo "[OS-INVARIANTS]"

if ! command -v python3 >/dev/null 2>&1; then
  echo "  skip: python3 not available"
  exit 0
fi

REGISTRY="${INVARIANTS_REGISTRY:-${REPO_ROOT}/.claude/invariants.json}"
export INVARIANTS_REGISTRY="$REGISTRY"

python3 - "$@" <<'PY'
import glob
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

# Bash already cd'd to git root
REPO_ROOT = Path.cwd()


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


def is_inv_key(k: str) -> bool:
    return isinstance(k, str) and k.startswith("INV-")


def git_ok() -> bool:
    try:
        subprocess.run(
            ["git", "-C", str(REPO_ROOT), "rev-parse", "--is-inside-work-tree"],
            check=True,
            capture_output=True,
            text=True,
        )
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False


def git_commit_count_since(since_dt: datetime, paths: list[str]) -> int:
    if not paths or not since_dt:
        return 0
    since_s = since_dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    try:
        p = subprocess.run(
            ["git", "-C", str(REPO_ROOT), "log", "--since", since_s, "--oneline", "--"] + paths,
            capture_output=True,
            text=True,
            check=False,
        )
        lines = [ln for ln in p.stdout.splitlines() if ln.strip()]
        return len(lines)
    except FileNotFoundError:
        return 0


def expand_watched(raw: list) -> list[str]:
    out = []
    cwd = REPO_ROOT
    for p in raw or []:
        if not isinstance(p, str):
            continue
        if "*" in p or "?" in p or "[" in p:
            for g in glob.glob(str(cwd / p), recursive=True):
                rel = str(Path(g).relative_to(cwd)).replace("\\", "/")
                out.append(rel)
        else:
            fp = cwd / p
            if fp.is_file() or fp.is_dir():
                out.append(p.replace("\\", "/"))
    return sorted(set(out))


def count_files_matching_patterns(scope_globs: list[str], patterns: list[str]) -> tuple[int, list[str]]:
    rx = [re.compile(x) for x in patterns]
    files = []
    for sg in scope_globs or []:
        for g in glob.glob(str(REPO_ROOT / sg), recursive=True):
            path = Path(g)
            if not path.is_file():
                continue
            try:
                text = path.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            if any(r.search(text) for r in rx):
                files.append(str(path.relative_to(REPO_ROOT)).replace("\\", "/"))
    return len(set(files)), sorted(set(files))


SKIP_SEGMENTS = {"node_modules", ".git", "dist", "build", ".next", "coverage", "__pycache__"}


def _walk_repo_files():
    for path in REPO_ROOT.rglob("*"):
        if not path.is_file():
            continue
        if SKIP_SEGMENTS.intersection(path.parts):
            continue
        suf = path.suffix.lower()
        if suf not in {".ts", ".tsx", ".js", ".jsx", ".md", ".json", ".yml", ".yaml"}:
            continue
        yield path


def probe_substring_in_repo(sub: str) -> bool:
    if not sub:
        return False
    for path in _walk_repo_files():
        try:
            if sub in path.read_text(encoding="utf-8", errors="replace"):
                return True
        except OSError:
            continue
    return False


def main():
    args = sys.argv[1:]
    apply_write = "--apply" in args
    for_path = None
    if "--for" in args:
        i = args.index("--for")
        for_path = args[i + 1] if i + 1 < len(args) else None

    reg_path = Path(os.environ["INVARIANTS_REGISTRY"]).expanduser().resolve()
    report_path = REPO_ROOT / ".claude" / "invariant-lifecycle-report.json"

    if not reg_path.is_file():
        print(f"  skip: no registry at {reg_path} (copy from templates/local/invariants-registry.seed.json)")
        return

    data = json.loads(reg_path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        print("  skip: invariants.json must be a JSON object keyed by INV-*")
        return

    inv_map = {k: v for k, v in data.items() if is_inv_key(k) and isinstance(v, dict)}
    git_works = git_ok()

    findings = []
    stale_for = []  # (inv_id, paths, n_commits, spec_snip)
    obsolete_hints = []
    genealogy = []

    for iid, inv in inv_map.items():
        watched = expand_watched(inv.get("watched_paths") or [])
        if for_path:
            fp = (for_path or "").replace("\\", "/")
            if not any(fp in w or w in fp for w in watched):
                continue

        last_v = parse_iso(inv.get("last_verified") or "")
        n_commits = 0
        if git_works and watched and last_v:
            n_commits = git_commit_count_since(last_v, watched)
        elif not watched:
            n_commits = 0

        risk = "LOW"
        if n_commits >= 3:
            risk = "HIGH"
        elif n_commits >= 1:
            risk = "MEDIUM"

        stale = bool(last_v and n_commits > 0 and inv.get("status") not in ("VIOLATED",))
        entry = {
            "id": iid,
            "name": inv.get("name"),
            "status_model": "STALE" if stale else (inv.get("status") or "UNKNOWN"),
            "commits_since_last_verified": n_commits,
            "watched_paths_resolved": watched,
            "staleness_risk": risk,
        }

        if stale:
            stale_for.append((iid, inv.get("name"), watched, n_commits, inv.get("spec", "")[:80]))
            entry["action"] = inv.get("action_required") or "re-verify invariant before proceeding"

        op = inv.get("obsolescence_probe") or {}
        if op.get("type") == "multi_file_pattern":
            lim = int(op.get("obsolete_if_matching_files_gt", 1))
            patterns = op.get("patterns") or []
            scopes = op.get("scope_globs") or []
            if patterns and scopes:
                cnt, files_hit = count_files_matching_patterns(scopes, patterns)
                if cnt > lim:
                    obsolete_hints.append(
                        {
                            "id": iid,
                            "kind": "MAY_BE_OBSOLETE",
                            "detail": op.get("description") or "spec may not match architecture",
                            "matching_files": files_hit[:30],
                            "count": cnt,
                            "threshold": lim,
                        }
                    )

        geo = inv.get("genealogy") or {}
        inc = geo.get("origin_incident")
        if inc:
            genealogy.append({"id": iid, "line": f"{iid} created from incident {inc}"})
        for cond in geo.get("origin_conditions") or []:
            note = (cond or {}).get("note")
            probe = (cond or {}).get("probe_substring_in_repo")
            if probe:
                present = probe_substring_in_repo(probe)
                suggest = (cond or {}).get("if_absent_suggest")
                if not present and suggest:
                    genealogy.append(
                        {
                            "id": iid,
                            "kind": "CONDITION_CHANGED",
                            "note": note,
                            "detail": suggest,
                        }
                    )
            rel_p = (cond or {}).get("still_relevant_if_path_exists")
            if rel_p and not (REPO_ROOT / rel_p).exists():
                genealogy.append(
                    {
                        "id": iid,
                        "kind": "PATH_GONE",
                        "path": rel_p,
                        "detail": "Genealogy anchor path missing — review invariant spec",
                    }
                )

        findings.append(entry)

    # Human-oriented blocks
    if for_path:
        rel = for_path.replace("\\", "/")
        hit = [s for s in stale_for if any(rel in w or w in rel for w in s[2])]
        if hit:
            print(f"  {len(hit)} invariant(s) are STALE for {rel}")
            for iid, name, watched, n_comm, _ in hit:
                print(f"    {iid} {name} — {n_comm} commit(s) since last_verified on watched path(s)")
                print(f"      ACTION: re-verify before proceeding")
        elif not inv_map:
            pass
        else:
            print(f"  no tracked STALE invariants for path: {rel}")

    if not for_path:
        all_stale = [s for s in stale_for]
        if all_stale:
            print(f"  summary: {len(all_stale)} STALE (git activity after last_verified)")
            for iid, name, watched, n_comm, _ in all_stale[:12]:
                ws = ", ".join(watched[:3]) + ("…" if len(watched) > 3 else "")
                print(f"    {iid} ({name}) — {n_comm} commit(s); watches: {ws}")
            if len(all_stale) > 12:
                print(f"    … +{len(all_stale) - 12} more (see invariant-lifecycle-report.json)")
        else:
            print("  summary: no STALE flags from git vs last_verified (or missing dates/paths)")

    for ob in obsolete_hints:
        print(f"  MAY_BE_OBSOLETE {ob['id']}: {ob['detail']}")
        print(f"    matching_files={ob['count']} (threshold {ob['threshold']}) — not necessarily a violation; update spec if intentional")

    for g in genealogy:
        if "line" in g:
            print(f"  GENEALOGY {g['line']}")
        elif g.get("kind") == "CONDITION_CHANGED":
            print(f"  GENEALOGY {g['id']}: {g.get('note') or 'condition'}")
            print(f"    → {g.get('detail')}")
        elif g.get("kind") == "PATH_GONE":
            print(f"  GENEALOGY {g['id']}: anchor {g.get('path')} missing — {g.get('detail')}")

    report = {
        "ts": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "registry": (
            str(reg_path.relative_to(REPO_ROOT))
            if str(reg_path).startswith(str(REPO_ROOT))
            else str(reg_path)
        ),
        "filter_for": for_path,
        "git_available": git_works,
        "findings": findings,
        "stale": [{"id": s[0], "name": s[1], "watched": s[2], "commits_since": s[3]} for s in stale_for],
        "obsolescence": obsolete_hints,
        "genealogy": genealogy,
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    try:
        rprel = report_path.relative_to(REPO_ROOT)
    except ValueError:
        rprel = report_path
    print(f"  report: {rprel}")

    if apply_write and inv_map:
        by_id = {f["id"]: f for f in findings}
        changed = False
        for iid, inv in inv_map.items():
            f = by_id.get(iid)
            if not f:
                continue
            if f["status_model"] == "STALE":
                inv["status"] = "STALE"
                inv["staleness_risk"] = f.get("staleness_risk", "MEDIUM")
                inv["last_consistency_scan"] = report["ts"]
                changed = True
        if changed:
            reg_path.write_text(json.dumps(data, indent=2), encoding="utf-8")
            print(f"  apply: updated statuses in {reg_path.name}")


if __name__ == "__main__":
    main()
PY

exit 0
