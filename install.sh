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

# 2. Global policies
for f in model-selection.md operating-modes.md engineering-governance.md production-safety.md; do
    copy_safe "$SOURCE/policies/$f" "$TARGET/policies/$f"
done

# 3. Global prompts
copy_safe "$SOURCE/prompts/session-start.md" "$TARGET/prompts/session-start.md"

echo ""
echo "Done. ~/.claude/ is ready."
echo ""
echo "Next steps:"
echo "  1. Install Claude Code: https://claude.ai/download"
echo "  2. Clone each project repo (contains .claude/ with session-state, learning-log, commands, agents)"
echo "  3. Open Claude Code in the project directory"
echo "  4. Type /session-start to recover operational context"
