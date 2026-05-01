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
# (internal_key, git grep -E pattern, short label for console — matches proposal wording)
CATEGORIES = [
    ("auth", r"jwt|jsonwebtoken|passport\.authenticate|express\.session", "jwt / session / passport"),
    ("billing", r"stripe|@stripe|payment_intent|billing|subscription\.(create|update)", "stripe / payment / billing"),
    ("crypto", r"bcrypt|scrypt|argon2|pbkdf2|createHash\(|\.createCipher", "bcrypt / crypto / hash"),
    ("migrations", r"migrate|migration|drizzle.*push|prisma[[:space:]]+db[[:space:]]+push|ALTER[[:space:]]+TABLE", "migrate / drizzle / prisma / ALTER TABLE"),
    ("publish", r"npm[[:space:]]+publish|semantic-release|release-it|production[[:space:]]+deploy", "publish / deploy / release"),
    ("secrets", r"apiKey|api_key|credential|client_secret|process\.env\.[A-Z0-9_]{4,}", "secret / token / apiKey"),
    ("destructive_sql", r"DELETE[[:space:]]+FROM|DROP[[:space:]]+TABLE|TRUNCATE[[:space:]]+TABLE", "DELETE / DROP / TRUNCATE"),
    ("comms_pii", r"sendEmail|sendMail|sendSMS|sendNotification|twilio\.messages", "sendEmail / SMS / notifications (PII)"),
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

hits: dict[str, list[tuple[str, str]]] = {}
for key, pat, human in CATEGORIES:
    for f in git_grep_files(pat):
        hits.setdefault(f, []).append((key, human))

if not hits:
    print("  ok: no heuristic risk hits in tracked code (or no matching extensions)")
    sys.exit(0)

new_surfaces = [(f, labs) for f, labs in sorted(hits.items()) if not is_declared(f)]
if not new_surfaces:
    print(f"  ok: {len(hits)} heuristic hit(s) covered by CLAUDE.md Critical Surfaces")
    sys.exit(0)

print(f"  review: {len(new_surfaces)} path(s) match risk heuristics but are not clearly declared in Critical Surfaces:")
for f, labs in new_surfaces[:25]:
    seen_h = set()
    print(f"  NEW SURFACE DETECTED: {f}")
    for _k, human in labs:
        if human in seen_h:
            continue
        seen_h.add(human)
        print(f"    pattern: {human}")
    print("    not declared in CLAUDE.md Critical Surfaces")
    print("    ACTION: review and add to Opus-mandatory list (CLAUDE.md → Critical Surfaces)")
if len(new_surfaces) > 25:
    print(f"  ... and {len(new_surfaces) - 25} more (cap 25)")
if not declared:
    print("  hint: Critical Surfaces section has no extracted paths — add backtick paths or bullets")
PY

exit 0
