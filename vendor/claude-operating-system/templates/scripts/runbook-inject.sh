#!/usr/bin/env bash
# Emit procedural runbook path + body for Context Salience Camada 1 injection. Exit 0; LF-only.
set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT" || exit 0

MODULE=""
if [[ "${1:-}" == "--module" ]]; then
  MODULE="${2:-}"
else
  MODULE="${1:-}"
fi
if [[ -z "$MODULE" ]]; then
  echo "[OS-RUNBOOK-INJECT] usage: runbook-inject.sh --module <path>" >&2
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[OS-RUNBOOK-INJECT] skip: python3 not available"
  exit 0
fi

export RI_REPO="$REPO_ROOT"
export RI_MODULE="${MODULE//\\//}"

python3 - <<'PY'
import os
import re
import sys
from pathlib import Path

ROOT = Path(os.environ["RI_REPO"])
mod = os.environ.get("RI_MODULE", "").strip().replace("\\", "/")
low = mod.lower()
for suf in (".ts", ".tsx", ".mts", ".cts"):
    if low.endswith(suf):
        mod = mod[: -len(suf)]
        break
slug = re.sub(r"[^a-zA-Z0-9/]+", "-", mod).replace("/", "-").strip("-").lower()
slug = re.sub(r"-+", "-", slug) or "module"
p = ROOT / ".claude" / "runbooks" / f"{slug}.md"
if not p.is_file():
    print(f"[OS-RUNBOOK-INJECT] no runbook for slug={slug} (expected {p.relative_to(ROOT)})")
    sys.exit(0)
print(f"[OS-RUNBOOK-INJECT] path: {p.relative_to(ROOT)}")
print("---BEGIN RUNBOOK---")
print(p.read_text(encoding="utf-8", errors="replace").rstrip())
print("---END RUNBOOK---")
PY

exit 0
