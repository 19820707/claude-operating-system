#!/usr/bin/env bash
# Heuristic ratchet — H1 (CRLF tracked), H5 (noise-only diffs), H10 (.sh CRLF). H10: LF-only.
set -euo pipefail

echo "[OS-HEURISTIC-RATCHET]"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "  skip: not a git repository"
  exit 0
fi

CONFIG=".local/heuristic-violations.json"
ENFORCE=0
RESET=0
for a in "$@"; do
  case "$a" in
    --enforce) ENFORCE=1 ;;
    --reset) RESET=1 ;;
  esac
done

mkdir -p .local

write_json() {
  local h1="$1" h5="$2" h10="$3" ts="$4" rb="$5"
  rb="${rb//\\/\\\\}"
  rb="${rb//\"/\\\"}"
  printf '{"schemaVersion":1,"h1":%s,"h5":%s,"h10":%s,"ts":"%s","reset_by":"%s"}\n' "$h1" "$h5" "$h10" "$ts" "$rb" > "$CONFIG"
}

read_h1() { grep -o '"h1"[[:space:]]*:[[:space:]]*[0-9]*' "$CONFIG" 2>/dev/null | grep -oE '[0-9]+$' | head -1 || echo 0; }
read_h5() { grep -o '"h5"[[:space:]]*:[[:space:]]*[0-9]*' "$CONFIG" 2>/dev/null | grep -oE '[0-9]+$' | head -1 || echo 0; }
read_h10() { grep -o '"h10"[[:space:]]*:[[:space:]]*[0-9]*' "$CONFIG" 2>/dev/null | grep -oE '[0-9]+$' | head -1 || echo 0; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "  skip: not a git repository"
  exit 0
fi

H1=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  if LC_ALL=C grep -q $'\r' "$f" 2>/dev/null; then
    H1=$((H1 + 1))
  fi
done < <(git ls-files 2>/dev/null | grep -E '\.(ts|tsx|js|jsx|json|md|sh|yml|yaml)$' || true)

H5=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  raw=$(git diff HEAD -- "$f" 2>/dev/null | wc -l | tr -d ' ')
  ign=$(git diff --ignore-cr-at-eol HEAD -- "$f" 2>/dev/null | wc -l | tr -d ' ')
  raw=${raw:-0}
  ign=${ign:-0}
  if [ "$raw" -gt 0 ] && [ "$ign" -eq 0 ] 2>/dev/null; then
    H5=$((H5 + 1))
  fi
done < <(git diff --name-only HEAD 2>/dev/null || true)

H10=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  if LC_ALL=C grep -q $'\r' "$f" 2>/dev/null; then
    H10=$((H10 + 1))
  fi
done < <(find . \( -path './.git' -o -path './node_modules' \) -prune -o -type f -name '*.sh' -print 2>/dev/null || true)

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo unknown)

if [ ! -f "$CONFIG" ]; then
  write_json "$H1" "$H5" "$H10" "$TS" "auto-init"
  echo "ok: baseline h1=${H1} h5=${H5} h10=${H10}"
  exit 0
fi

if [ "$RESET" -eq 1 ]; then
  write_json "$H1" "$H5" "$H10" "$TS" "reset:${USER:-unknown}"
  echo "ok: baseline reset h1=${H1} h5=${H5} h10=${H10}"
  exit 0
fi

B1=$(read_h1); B5=$(read_h5); B10=$(read_h10)
B1=${B1:-0}; B5=${B5:-0}; B10=${B10:-0}

REG=0
if [ "$H1" -gt "$B1" ]; then echo "RATCHET: H1 regression +$((H1 - B1)) (${B1} -> ${H1})"; REG=1; fi
if [ "$H5" -gt "$B5" ]; then echo "RATCHET: H5 regression +$((H5 - B5)) (${B5} -> ${H5})"; REG=1; fi
if [ "$H10" -gt "$B10" ]; then echo "RATCHET: H10 regression +$((H10 - B10)) (${B10} -> ${H10})"; REG=1; fi

if [ "$REG" -eq 1 ]; then
  if [ "$ENFORCE" -eq 1 ]; then
    exit 1
  fi
  exit 0
fi

if [ "$H1" -lt "$B1" ] || [ "$H5" -lt "$B5" ] || [ "$H10" -lt "$B10" ]; then
  write_json "$H1" "$H5" "$H10" "$TS" "auto-improved"
  echo "ok: improved baseline updated (h1=${H1} h5=${H5} h10=${H10})"
  exit 0
fi

echo "ok: stable h1=${H1} h5=${H5} h10=${H10}"
exit 0
