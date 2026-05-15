#!/usr/bin/env bash
# Dynamic risk surface scanner — filesystem walk + patterns vs CLAUDE.md Critical Surfaces. H10: LF-only; exit 0.
set -euo pipefail

echo "[OS-RISK-SCAN]"

if ! command -v python3 >/dev/null 2>&1; then
  echo "  skip: python3 not available"
  exit 0
fi

mkdir -p .claude

python3 - <<'PY'
import json, os, re
from datetime import datetime, timezone
from pathlib import Path

SKIP_DIRS = {".git", "node_modules", "dist", ".claude", ".next", "build", "coverage", ".turbo", "vendor", ".local"}
TEXT_EXT = {
    ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".mts", ".cts", ".vue", ".svelte",
    ".py", ".go", ".rs", ".java", ".kt", ".sql", ".sh", ".yml", ".yaml", ".json",
    ".md", ".rb", ".php",
}

PATTERNS = [
    ("AUTH", re.compile(r"jwt|jsonwebtoken|passport\.authenticate|express-session|express\.session|connect-pg-simple", re.I)),
    ("BILLING", re.compile(r"stripe|paymentIntent|subscription|webhook.*payment|billing", re.I)),
    ("CRYPTO", re.compile(r"bcrypt|createHash|crypto\.subtle|pbkdf2|argon2", re.I)),
    ("MIGRATE", re.compile(r"drizzle.*push|migrate\(\)|ALTER\s+TABLE|CREATE\s+TABLE|DROP\s+TABLE", re.I)),
    ("PUBLISH", re.compile(r"npm.*publish|deploy\.sh|release\.sh", re.I)),
    ("SECRETS", re.compile(r"process\.env\.(SECRET|KEY|TOKEN|PASSWORD|STRIPE|JWT)", re.I)),
    ("DESTRUCTIVE", re.compile(r"DELETE\s+FROM|DROP\s+TABLE|TRUNCATE", re.I)),
    ("PII", re.compile(r"sendEmail|sendSMS|sendNotification|personalData|gdpr", re.I)),
]

def load_declared() -> set[str]:
    out: set[str] = set()
    cl = Path("CLAUDE.md")
    if not cl.is_file():
        return out
    text = cl.read_text(encoding="utf-8", errors="replace")
    sec = False
    for line in text.splitlines():
        if line.startswith("## Critical Surfaces"):
            sec = True
            continue
        if sec and line.startswith("## ") and "Critical Surfaces" not in line:
            break
        if not sec:
            continue
        if "server/" in line or "client/" in line:
            for m in re.finditer(r"`([^`]+)`", line):
                out.add(m.group(1).strip().replace("\\", "/"))
            for m in re.finditer(r"([\w./-]*(?:server|client)/[\w./-]+)", line):
                p = m.group(1).strip().strip("`").replace("\\", "/")
                if "/" in p:
                    out.add(p)
    return out


def norm(p: str) -> str:
    return p.replace("\\", "/").lstrip("./")


def is_declared(rel: str, declared: set[str]) -> bool:
    r = norm(rel).lower()
    for d in declared:
        dn = norm(d).lower().strip("*")
        if not dn:
            continue
        if dn in r or r in dn:
            return True
        core = dn.strip("*").strip("/")
        if core and core in r:
            return True
    return False


def should_skip_dir(name: str) -> bool:
    return name in SKIP_DIRS or name.startswith(".")


def iter_repo_files(root: Path):
    for dirpath, dirnames, filenames in os.walk(root, topdown=True):
        dirnames[:] = [d for d in dirnames if not should_skip_dir(d)]
        for fn in filenames:
            p = Path(dirpath) / fn
            if p.suffix.lower() not in TEXT_EXT and p.suffix:
                continue
            try:
                if p.stat().st_size > 1_500_000:
                    continue
            except OSError:
                continue
            yield p


def scan_file(path: Path) -> list[str]:
    try:
        data = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    hits = []
    for name, rx in PATTERNS:
        if rx.search(data):
            hits.append(name)
    return hits


def main():
    root = Path(".").resolve()
    declared = load_declared()
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    detected: list[dict] = []
    undeclared: list[dict] = []
    confirmed: list[str] = []

    for fp in iter_repo_files(root):
        rel = norm(str(fp.relative_to(root)))
        hits = scan_file(fp)
        if not hits:
            continue
        uniq = sorted(set(hits))
        rec = {"path": rel, "patterns": uniq}
        detected.append(rec)
        if is_declared(rel, declared):
            print(f"  ok: confirmed {rel}")
            confirmed.append(rel)
        else:
            for pname in uniq:
                print(f"  NEW SURFACE DETECTED: {rel}")
                print(f"    pattern: {pname}")
                print("    not declared in CLAUDE.md Critical Surfaces")
                print("    ACTION: review and add to Opus-mandatory list")
            undeclared.append(rec)

    out = {
        "scanned_at": ts,
        "declared": sorted(declared),
        "detected": detected,
        "undeclared": undeclared,
    }
    Path(".claude/risk-surfaces.json").write_text(
        json.dumps(out, indent=2), encoding="utf-8"
    )
    print(f"  wrote .claude/risk-surfaces.json ({len(detected)} risky files, {len(undeclared)} undeclared records)")


if __name__ == "__main__":
    main()
PY

exit 0
