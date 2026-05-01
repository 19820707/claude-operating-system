#!/usr/bin/env bash
# Public contract extraction & delta (grep-style, no compiler). Exit 0; LF-only.
set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT" || exit 0

usage() {
  cat <<'U' >&2
Usage:
  contract-delta.sh --extract <filepath>
  contract-delta.sh --snapshot <filepath>
  contract-delta.sh --compare <filepath> --baseline <contracts-json>
Writes .claude/contracts/<slug>.json for extract/snapshot; prints [OS-CONTRACT] / [OS-CONTRACT-DELTA].
U
}

if ! command -v python3 >/dev/null 2>&1; then
  echo "[OS-CONTRACT] skip: python3 required for JSON contract bundle"
  exit 0
fi

if [[ $# -eq 0 ]]; then
  usage
  exit 0
fi

export CD_REPO="$REPO_ROOT"
export CD_MODE="${1:-}"
shift || true
export CD_ARGS_JSON
CD_ARGS_JSON="$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' -- "$@")"

python3 - <<'PY'
from __future__ import annotations

import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(os.environ["CD_REPO"])
argv = json.loads(os.environ.get("CD_ARGS_JSON", "[]"))


def slug_contract(rel: str) -> str:
    p = rel.strip().replace("\\", "/")
    low = p.lower()
    for suf in (".ts", ".tsx", ".mts", ".cts"):
        if low.endswith(suf):
            p = p[: -len(suf)]
            break
    s = re.sub(r"[^a-zA-Z0-9/]+", "-", p).replace("/", "-").strip("-").lower()
    return re.sub(r"-+", "-", s) or "module"


def read_rel(path_arg: str) -> tuple[Path, str]:
    rel = path_arg.strip().replace("\\", "/")
    abs_p = ROOT / rel
    if not abs_p.is_file():
        raise FileNotFoundError(rel)
    text = abs_p.read_text(encoding="utf-8", errors="replace")
    return abs_p, rel


def extract_lines(text: str) -> dict:
    """Mirror grep-style export discovery (no TS compiler)."""
    exports = []
    signatures = []
    type_fields = []

    for line in text.splitlines():
        raw = line.strip()
        if re.match(
            r"^export\s+(async\s+)?(function|class|const|type|interface|enum)\s+\w+",
            raw,
        ):
            exports.append(raw[:500])
        m = re.match(
            r"^export\s+async\s+function\s+(\w+)\s*\(([^)]*)\)", raw
        ) or re.match(r"^export\s+function\s+(\w+)\s*\(([^)]*)\)", raw)
        if m:
            signatures.append({"name": m.group(1), "params_visible": m.group(2).strip()[:400]})

    in_block = None
    block_name = None
    buf = []
    for line in text.splitlines():
        m = re.match(
            r"^export\s+(type|interface)\s+(\w+)\s*(\{|<)", line.strip()
        )
        if m:
            in_block = m.group(1)
            block_name = m.group(2)
            buf = [line.rstrip()]
            if "{" not in line:
                continue
        if in_block and block_name:
            buf.append(line.rstrip())
            if line.rstrip().endswith("}") and in_block == "interface":
                body = "\n".join(buf)[:8000]
                type_fields.append({"name": block_name, "kind": in_block, "raw": body})
                in_block = None
                block_name = None
            elif in_block == "type" and ";" in line and line.strip().endswith(";"):
                body = "\n".join(buf)[:4000]
                type_fields.append({"name": block_name, "kind": "type", "raw": body})
                in_block = None
                block_name = None

    return {"exports": exports, "signatures": signatures, "type_fields": type_fields}


def classify_delta(cur: dict, base: dict) -> list[dict]:
    rows = []
    base_sigs = {s["name"]: s for s in base.get("signatures", []) if isinstance(s, dict)}
    cur_sigs = {s["name"]: s for s in cur.get("signatures", []) if isinstance(s, dict)}
    for name, cs in cur_sigs.items():
        if name not in base_sigs:
            rows.append(
                {
                    "kind": "ADDITIVE",
                    "symbol": name,
                    "detail": "new exported function",
                }
            )
            continue
        bp = base_sigs[name].get("params_visible", "")
        cp = cs.get("params_visible", "")
        if bp != cp:
            broke = False
            if cp.count(",") > bp.count(",") and "?" not in cp.split(",")[-1]:
                broke = True
            if re.search(r"\w+\s*:\s*\w+", cp) and "?" not in cp and bp != cp:
                broke = True
            rows.append(
                {
                    "kind": "BREAKING" if broke else "UNKNOWN",
                    "symbol": name,
                    "detail": f"signature changed: {bp!r} -> {cp!r}",
                }
            )
    for name in base_sigs:
        if name not in cur_sigs:
            rows.append(
                {"kind": "BREAKING", "symbol": name, "detail": "removed export function"}
            )

    be = set(base.get("exports") or [])
    ce = set(cur.get("exports") or [])
    for e in ce - be:
        if not any(r.get("symbol") in e for r in rows if "function" in e):
            rows.append({"kind": "ADDITIVE", "symbol": e[:80], "detail": "new export line"})
    for e in be - ce:
        rows.append({"kind": "BREAKING", "symbol": e[:80], "detail": "removed export line"})

    for tf in cur.get("type_fields", []) or []:
        name = tf.get("name")
        raw = tf.get("raw", "")
        base_tf = next(
            (x for x in (base.get("type_fields") or []) if x.get("name") == name), None
        )
        if not base_tf:
            rows.append({"kind": "ADDITIVE", "symbol": name, "detail": "new type/interface"})
            continue
        br, cr = base_tf.get("raw", ""), raw
        if br == cr:
            continue
        if "?:" in cr or "?: " in cr or "optional" in cr.lower():
            rows.append({"kind": "ADDITIVE", "symbol": name, "detail": "type/interface body changed (optional hints)"})
        elif re.search(r"\w+\s*:\s*\w+", cr) and "?:" not in cr:
            rows.append(
                {
                    "kind": "BREAKING",
                    "symbol": name,
                    "detail": "type/interface may add required field",
                }
            )
        else:
            rows.append({"kind": "NEUTRAL", "symbol": name, "detail": "body changed"})
    return rows


def main():
    mode = os.environ.get("CD_MODE", "")
    args = argv
    if mode in ("-h", "--help", ""):
        print("usage: --extract|--snapshot <file> | --compare <file> --baseline <json>", file=sys.stderr)
        return

    if mode in ("--extract", "--snapshot"):
        rel = args[0] if args else None
        if not rel:
            print("[OS-CONTRACT] ERROR: filepath required", file=sys.stderr)
            return
        _, rel_norm = read_rel(rel)
        text = (ROOT / rel_norm).read_text(encoding="utf-8", errors="replace")
        slug = slug_contract(rel_norm)
        out_dir = ROOT / ".claude" / "contracts"
        out_dir.mkdir(parents=True, exist_ok=True)
        bundle = {
            "file": rel_norm.replace("\\", "/"),
            "extracted_at": datetime.now(timezone.utc)
            .isoformat()
            .replace("+00:00", "Z"),
            **extract_lines(text),
        }
        outp = out_dir / f"{slug}.json"
        if mode == "--snapshot" and outp.is_file():
            print(
                f"[OS-CONTRACT] snapshot skipped (exists): {outp.relative_to(ROOT)} — use --extract to overwrite or delete for fresh baseline"
            )
            return
        outp.write_text(json.dumps(bundle, indent=2), encoding="utf-8", newline="\n")
        n = len(bundle["exports"]) + len(bundle["signatures"]) + len(bundle["type_fields"])
        print(f"[OS-CONTRACT] extracted {n} contract rows from {rel_norm} -> {outp.relative_to(ROOT)}")
        return

    if mode == "--compare":
        rel = None
        baseline_path = None
        i = 0
        while i < len(args):
            if args[i] == "--baseline" and i + 1 < len(args):
                baseline_path = args[i + 1]
                i += 2
            elif args[i] == "--compare" and i + 1 < len(args):
                rel = args[i + 1]
                i += 2
            else:
                if rel is None and not str(args[i]).startswith("--"):
                    rel = args[i]
                i += 1
        if not rel or not baseline_path:
            print("[OS-CONTRACT] ERROR: --compare <file> --baseline <json>", file=sys.stderr)
            return
        bp = Path(baseline_path)
        if not bp.is_file():
            print(f"[OS-CONTRACT] ERROR: baseline missing {baseline_path}", file=sys.stderr)
            return
        base = json.loads(bp.read_text(encoding="utf-8", errors="replace"))
        _, rel_norm = read_rel(rel)
        text = (ROOT / rel_norm).read_text(encoding="utf-8", errors="replace")
        cur = {
            "file": rel_norm.replace("\\", "/"),
            "extracted_at": datetime.now(timezone.utc)
            .isoformat()
            .replace("+00:00", "Z"),
            **extract_lines(text),
        }
        deltas = classify_delta(cur, base)
        print(f"[OS-CONTRACT-DELTA] {rel_norm}")
        worst = "NEUTRAL"
        rank = {"BREAKING": 3, "UNKNOWN": 2, "ADDITIVE": 2, "NEUTRAL": 1}
        for d in deltas:
            k = d["kind"]
            if rank.get(k, 0) > rank.get(worst, 0):
                worst = k
            print(f"  {k}: {d.get('symbol')} — {d.get('detail')}")
        br = [x for x in deltas if x["kind"] == "BREAKING"]
        ad = [x for x in deltas if x["kind"] == "ADDITIVE"]
        if br and ad:
            print(
                "  CONFLICT: function/type delta mixes BREAKING and ADDITIVE — DECISION REQUIRED (required vs optional rollout)"
            )
        meta = ROOT / ".claude" / "contracts" / ".last-compare.json"
        meta.parent.mkdir(parents=True, exist_ok=True)
        meta.write_text(
            json.dumps(
                {"file": rel_norm, "deltas": deltas, "worst": worst},
                indent=2,
            ),
            encoding="utf-8",
            newline="\n",
        )
        return

    print("[OS-CONTRACT] unknown mode", file=sys.stderr)


if __name__ == "__main__":
    try:
        main()
    except FileNotFoundError as e:
        print(f"[OS-CONTRACT] ERROR: {e}", file=sys.stderr)
    except OSError as e:
        print(f"[OS-CONTRACT] ERROR: {e}", file=sys.stderr)
PY

exit 0
