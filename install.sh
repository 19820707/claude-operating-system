#!/usr/bin/env bash
# install.sh — Bootstrap ~/.claude/ from claude-operating-system
# Run after cloning this repo on a new machine:
#   bash install.sh
#
# Safe to re-run: copies only, never deletes existing files.
#
# Options:
#   --target <path>   Override destination (default: $HOME/.claude)
#   --dry-run         Print what would be copied without writing anything

set -euo pipefail

SOURCE="$(cd "$(dirname "$0")" && pwd)"
TARGET="${HOME}/.claude"
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)
            TARGET="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: bash install.sh [--target <path>] [--dry-run]" >&2
            exit 1
            ;;
    esac
done

copy_safe() {
    local from="$1"
    local to="$2"
    local dir
    dir="$(dirname "$to")"

    if [[ ! -d "$dir" ]]; then
        if [[ "$DRY_RUN" == false ]]; then
            mkdir -p "$dir"
        fi
        echo "  mkdir  $dir"
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo "  [dry]  $from -> $to"
    else
        cp -f "$from" "$to"
        echo "  copied $from -> $to"
    fi
}

echo ""
echo "claude-operating-system install"
echo "Source : $SOURCE"
echo "Target : $TARGET"
if [[ "$DRY_RUN" == true ]]; then echo "[DRY RUN - no files written]"; fi
echo ""

# 1. Global CLAUDE.md
copy_safe "$SOURCE/CLAUDE.md" "$TARGET/CLAUDE.md"

# 2. Global policies (all *.md in policies/)
shopt -s nullglob
for from in "$SOURCE/policies"/*.md; do
    base="$(basename "$from")"
    copy_safe "$from" "$TARGET/policies/$base"
done
shopt -u nullglob

# 3. Global prompts (all *.md in prompts/)
shopt -s nullglob
for from in "$SOURCE/prompts"/*.md; do
    base="$(basename "$from")"
    copy_safe "$from" "$TARGET/prompts/$base"
done

# 4. Global heuristics (all *.md in heuristics/)
if [[ -d "$SOURCE/heuristics" ]]; then
    for from in "$SOURCE/heuristics"/*.md; do
        [[ -e "$from" ]] || continue
        base="$(basename "$from")"
        copy_safe "$from" "$TARGET/heuristics/$base"
    done
fi
shopt -u nullglob

echo ""
echo "Done. ~/.claude/ is ready."
echo ""
echo "Next steps:"
echo "  1. Install Claude Code: https://claude.ai/download"
echo '  2. New project (Windows): powershell -ExecutionPolicy Bypass -File ./init-project.ps1 -ProjectPath "$env:USERPROFILE\claude\<project>"  (or -Name <project>)'
echo "  3. Clone each project repo (contains .claude/ with session-state, learning-log, commands, agents)"
echo "  4. Open Claude Code in the project directory"
echo "  5. Type /session-start to recover operational context"
