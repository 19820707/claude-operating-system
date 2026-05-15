#!/usr/bin/env bash
# deploy-check.sh — Pre-deploy validation: Dockerfile, Vite, Railway configs
# H11: Vite env injection | H12: envsubst filter | H13: Node version | H14: Vite externals
# Usage: bash deploy-check.sh [--dockerfile|--vite|--railway|--all]
# LF-only

set -euo pipefail

ISSUES=0

_fail() { echo "FAIL : $1"; ISSUES=$((ISSUES + 1)); }
_ok()   { echo "ok   : $1"; }
_warn() { echo "WARN : $1"; }

check_dockerfile() {
  echo "[DEPLOY-CHECK] Dockerfile"
  if [ ! -f "Dockerfile" ]; then
    _warn "Dockerfile not found — skipping"
    return
  fi

  # H13: Node version in FROM must match engines.node in package.json
  local docker_node=""
  local engines_node=""
  local from_line
  from_line=$(grep -m1 "^FROM node:" Dockerfile 2>/dev/null || true)
  if [ -n "$from_line" ]; then
    docker_node=$(echo "$from_line" | sed -E 's/FROM node:([0-9]+).*/\1/')
  fi
  if [ -f "package.json" ] && command -v node >/dev/null 2>&1; then
    engines_node=$(node << 'EOF'
try {
  var e = (require('./package.json').engines || {}).node || '';
  var m = e.match(/([0-9]+)/);
  console.log(m ? m[1] : '');
} catch(e) { console.log(''); }
EOF
2>/dev/null || true)
  fi
  if [ -n "$docker_node" ] && [ -n "$engines_node" ]; then
    if [ "$docker_node" -lt "$engines_node" ]; then
      _fail "Dockerfile node:$docker_node < engines.node $engines_node — update FROM node:$engines_node (H13)"
    else
      _ok "FROM node:$docker_node — matches engines.node >=$engines_node"
    fi
  elif [ -n "$docker_node" ]; then
    _ok "FROM node:$docker_node found (no engines.node to compare)"
  fi

  # H11: every VITE_* var referenced in vite config must have ARG in Dockerfile
  local vite_conf=""
  [ -f "vite.config.ts" ] && vite_conf="vite.config.ts"
  [ -f "vite.config.js" ] && vite_conf="vite.config.js"
  if [ -n "$vite_conf" ]; then
    local vite_vars
    vite_vars=$(grep -oE 'VITE_[A-Z_]+' "$vite_conf" | sort -u || true)
    if [ -z "$vite_vars" ]; then
      _ok "no VITE_* vars referenced in $vite_conf"
    else
      for var in $vite_vars; do
        if grep -q "^ARG $var" Dockerfile 2>/dev/null; then
          _ok "ARG $var declared"
        else
          _fail "ARG $var missing in Dockerfile — required for Vite build-time injection (H11)"
        fi
      done
    fi
  fi

  # H12: envsubst must have explicit single-quoted filter
  if grep -q "envsubst" Dockerfile 2>/dev/null; then
    if grep -E "envsubst '\\\$[A-Z_]+'" Dockerfile 2>/dev/null | grep -q .; then
      _ok "envsubst has explicit single-quoted filter"
    else
      _fail "envsubst missing explicit filter — use envsubst '\$PORT' not bare envsubst (H12)"
    fi
  fi
}

check_vite() {
  echo "[DEPLOY-CHECK] Vite"
  local vite_conf=""
  [ -f "vite.config.ts" ] && vite_conf="vite.config.ts"
  [ -f "vite.config.js" ] && vite_conf="vite.config.js"
  if [ -z "$vite_conf" ]; then
    _warn "vite.config.ts/js not found — skipping"
    return
  fi
  if ! command -v node >/dev/null 2>&1; then
    _warn "node not available — skipping rollupOptions.external check"
    return
  fi

  # H14: rollupOptions.external must only contain native (capacitor/electron) entries
  local externals
  externals=$(node << 'EOF'
var fs = require('fs');
var conf = ['vite.config.ts', 'vite.config.js'].find(function(f) { return fs.existsSync(f); });
if (!conf) process.exit(0);
var src = fs.readFileSync(conf, 'utf8');
var m = src.match(/external\s*:\s*\[([^\]]+)\]/);
if (!m) process.exit(0);
var items = (m[1].match(/['"][^'"]+['"]/g) || []).map(function(s) { return s.replace(/['"]/g, ''); });
items.forEach(function(i) { if (i) console.log(i); });
EOF
2>/dev/null || true)

  if [ -z "$externals" ]; then
    _ok "no rollupOptions.external entries found"
    return
  fi
  while IFS= read -r ext; do
    [ -z "$ext" ] && continue
    if echo "$ext" | grep -qE '^@capacitor/|^electron$|^electron/'; then
      _ok "external '$ext' is native — allowed"
    else
      _fail "$ext found in rollupOptions.external — must be bundled (H14)"
    fi
  done <<< "$externals"
}

check_railway() {
  echo "[DEPLOY-CHECK] Railway"
  if [ ! -f "railway.json" ]; then
    _ok "no railway.json found"
    return
  fi
  if ! command -v node >/dev/null 2>&1; then
    _warn "node not available — skipping railway.json parse"
    return
  fi

  local has_start
  has_start=$(node << 'EOF'
try {
  var r = require('./railway.json');
  var s = (r.deploy || {}).startCommand || r.startCommand || '';
  console.log(s ? 'yes' : 'no');
} catch(e) { console.log('no'); }
EOF
2>/dev/null || echo "no")

  local has_cmd
  has_cmd=$(grep -c "^CMD " Dockerfile 2>/dev/null || echo "0")

  if [ "$has_start" = "yes" ] && [ "$has_cmd" -gt 0 ]; then
    _warn "railway.json has startCommand AND Dockerfile has CMD — CMD will be ignored by Railway"
  elif [ "$has_start" = "yes" ]; then
    _ok "startCommand in railway.json (no Dockerfile CMD conflict)"
  else
    _ok "no startCommand in railway.json (Dockerfile CMD takes precedence)"
  fi
}

_print_result() {
  echo ""
  if [ "$ISSUES" -gt 0 ]; then
    echo "RESULT: $ISSUES issue(s) found — fix before push"
    exit 1
  else
    echo "RESULT: clean"
    exit 0
  fi
}

MODE="${1:---all}"
case "$MODE" in
  --dockerfile)
    check_dockerfile
    _print_result
    ;;
  --vite)
    check_vite
    _print_result
    ;;
  --railway)
    check_railway
    _print_result
    ;;
  *)
    check_dockerfile
    echo ""
    check_vite
    echo ""
    check_railway
    _print_result
    ;;
esac
