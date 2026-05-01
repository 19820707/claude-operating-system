#!/usr/bin/env bash
# Dynamic Risk Surface Scanner — infers high-risk code via git-grep heuristics vs CLAUDE.md declarations.
# Advisory only; exit 0 always. H10: LF-only.
set -euo pipefail

echo "[OS-RISK-SCAN]"

if ! command -v python3 >/dev/null 2>&1; then
  echo "  skip: python3 not available"
  exit 0
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "  skip: not a git repository"
  exit 0
fi

python3 - <<'PY'
import re, subprocess, sys
from pathlib import Path

CLAUDE = Path("CLAUDE.md")
if not CLAUDE.is_file():
    print("  skip: no CLAUDE.md")
    sys.exit(0)

text = CLAUDE.read_text(encoding="utf-8", errors="replace")
declared: set[str] = set()
in_crit = False
for line in text.splitlines():
    if line.startswith("## Critical Surfaces"):
        in_crit = True
        continue
    if in_crit and line.startswith("## ") and "Critical Surfaces" not in line:
        break
    if not in_crit:
        continue
    if line.strip().startswith("<!--"):
        continue
    for m in re.finditer(r"`([^`]+)`", line):
        declared.add(m.group(1).strip().replace("\\", "/"))
    m2 = re.match(r"^\s*-\s*`([^`]+)`", line)
    if m2:
        declared.add(m2.group(1).strip().replace("\\", "/"))
    m3 = re.match(r"^\s*-\s*(\S+)", line)
    if m3 and not m3.group(1).startswith("<!--"):
        p = m3.group(1).strip().rstrip("`").lstrip("`")
        if "/" in p or p.endswith((".ts", ".tsx", ".js", ".jsx", ".mts")):
            declared.add(p.replace("\\", "/"))

# Categories: (label, combined ripgrep-style pattern)
# Note: heuristic only — expect false positives; tune CLAUDE.md Critical Surfaces.
# git grep -E (ERE): avoid PCRE-only tokens like \b
CATEGORIES = [
    ("auth/jwt/session", r"jwt|jsonwebtoken|passport\.authenticate|express\.session"),
    ("billing/payments", r"stripe|@stripe|payment_intent|billing|subscription\.(create|update)"),
    ("crypto/passwords", r"bcrypt|scrypt|argon2|pbkdf2|createHash\(|\.createCipher"),
    ("migrations/schema", r"migrate|migration|drizzle.*push|prisma[[:space:]]+db[[:space:]]+push|ALTER[[:space:]]+TABLE"),
    ("publish/deploy", r"npm[[:space:]]+publish|semantic-release|release-it|production[[:space:]]+deploy"),
    ("secrets/config", r"apiKey|api_key|credential|client_secret|process\.env\.[A-Z0-9_]{4,}"),
    ("destructive-sql", r"DELETE[[:space:]]+FROM|DROP[[:space:]]+TABLE|TRUNCATE[[:space:]]+TABLE"),
    ("outbound-comms", r"sendEmail|sendMail|sendSMS|sendNotification|twilio\.messages"),
]

PATHSPECS = [
    "*.ts",
    "*.tsx",
    "*.js",
    "*.jsx",
    "*.mts",
    "*.cts",
    "*.mjs",
    "*.cjs",
    "*.vue",
    "*.py",
    "*.go",
]


def norm(p: str) -> str:
    return p.replace("\\", "/").lstrip("./")


def is_declared(rel: str) -> bool:
    r = norm(rel).lower()
    if not declared:
        return False
    for d in declared:
        dn = norm(d).lower().strip("*")
        if not dn:
            continue
        if dn in r or r in dn:
            return True
        # glob-ish **/auth/** → strip stars
        core = dn.strip("*").strip("/")
        if core and core in r:
            return True
    return False


def git_grep_files(pattern: str) -> set[str]:
    cmd = ["git", "-c", "core.quotepath=false", "grep", "-l", "-E", "--no-color", pattern, "--"] + PATHSPECS
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.DEVNULL, text=True)
    except subprocess.CalledProcessError as e:
        if e.returncode == 1:
            return set()
        return set()
    return {norm(x) for x in out.splitlines() if x.strip()}

hits: dict[str, list[str]] = {}
for label, pat in CATEGORIES:
    for f in git_grep_files(pat):
        hits.setdefault(f, []).append(label)

if not hits:
    print("  ok: no heuristic risk hits in tracked code (or no matching extensions)")
    sys.exit(0)

new_surfaces = [(f, labs) for f, labs in sorted(hits.items()) if not is_declared(f)]
if not new_surfaces:
    print(f"  ok: {len(hits)} heuristic hit(s) covered by CLAUDE.md Critical Surfaces")
    sys.exit(0)

print(f"  review: {len(new_surfaces)} path(s) match risk heuristics but are not clearly declared in Critical Surfaces:")
for f, labs in new_surfaces[:25]:
    uniq = ", ".join(sorted(set(labs)))
    print(f"  NEW SURFACE DETECTED: {f}")
    print(f"    patterns: {uniq}")
    print("    ACTION: add to CLAUDE.md → Critical Surfaces (Opus mandatory) if this path is production-critical")
if len(new_surfaces) > 25:
    print(f"  ... and {len(new_surfaces) - 25} more (cap 25)")
if not declared:
    print("  hint: Critical Surfaces section has no extracted paths — add backtick paths or bullets")
PY

exit 0
