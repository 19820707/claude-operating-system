#!/usr/bin/env bash
# Change Simulation Protocol — contract delta + blast radius + invariant at-risk (no repo writes).
# Non-blocking; exit 0; LF-only.
set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT" || exit 0

usage() {
  cat <<'U' >&2
Usage: change-simulation.sh --change "description" [--baseline path] [--proposed path] [--files "a.ts,b.ts"]
  --baseline / --proposed: optional; if both set, runs contract delta (TypeScript required in project).
  --files: comma-separated repo-relative paths as change seeds (blast + invariant scope).
  Writes .claude/simulation-report.json and prints [OS-SIMULATION] summary.
U
}

CHANGE_DESC=""
BASELINE=""
PROPOSED=""
FILES_CSV=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --change) CHANGE_DESC="${2:-}"; shift 2 ;;
    --baseline) BASELINE="${2:-}"; shift 2 ;;
    --proposed) PROPOSED="${2:-}"; shift 2 ;;
    --files) FILES_CSV="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[OS-SIMULATION] unknown arg: $1" >&2; usage; exit 0 ;;
  esac
done

mkdir -p "${REPO_ROOT}/.claude" 2>/dev/null || true
DELTA_FILE="${REPO_ROOT}/.claude/.simulation-delta-$$.json"
DELTA_SKIPPED='{"overall":"SKIPPED","details":[],"conflicts":[],"note":"no baseline/proposed pair"}'
printf '%s' "$DELTA_SKIPPED" >"$DELTA_FILE"

SIM_SCRIPT="${REPO_ROOT}/.claude/invariant-engine/simulate-contract-delta.cjs"
if [[ -n "$BASELINE" && -n "$PROPOSED" ]]; then
  if [[ -f "$SIM_SCRIPT" ]] && command -v node >/dev/null 2>&1; then
    node "$SIM_SCRIPT" --baseline "$BASELINE" --proposed "$PROPOSED" >"$DELTA_FILE" 2>/dev/null || true
  else
    printf '%s' '{"overall":"UNKNOWN","error":"missing_sim","message":"node or simulate-contract-delta.cjs unavailable"}' >"$DELTA_FILE"
  fi
fi

export CS_REPO="$REPO_ROOT"
export CS_DELTA_FILE="$DELTA_FILE"
export CS_FILES_CSV="$FILES_CSV"
export CS_CHANGE_DESC="${CHANGE_DESC:-(unspecified)}"

if ! command -v node >/dev/null 2>&1; then
  echo "[OS-SIMULATION] skip: node not available"
  exit 0
fi

node <<'NODE'
"use strict";

const fs = require("fs");
const path = require("path");

const ROOT = process.env.CS_REPO || process.cwd();
let delta;
try {
  const p = process.env.CS_DELTA_FILE;
  const raw = p && fs.existsSync(p) ? fs.readFileSync(p, "utf8") : "{}";
  delta = JSON.parse(raw || "{}");
} catch {
  delta = { overall: "UNKNOWN", details: [], parse_error: true };
}
const filesCsv = process.env.CS_FILES_CSV || "";
const changeDesc = process.env.CS_CHANGE_DESC || "(unspecified)";
const seeds = filesCsv
  .split(",")
  .map((s) => s.trim().replace(/\\/g, "/"))
  .filter(Boolean);

if (delta.baseline && !seeds.includes(delta.baseline)) seeds.unshift(delta.baseline);
if (delta.proposed && !seeds.includes(delta.proposed)) seeds.push(delta.proposed);

const kgPath = path.join(ROOT, ".claude", "knowledge-graph.json");
let kg = { nodes: {}, edges: [] };
if (fs.existsSync(kgPath)) {
  try {
    kg = JSON.parse(fs.readFileSync(kgPath, "utf8"));
  } catch {
    /* keep default */
  }
}

const edges = Array.isArray(kg.edges) ? kg.edges : [];
const rev = new Map();
for (const e of edges) {
  if (!e || typeof e.from !== "string" || typeof e.to !== "string") continue;
  if (!rev.has(e.to)) rev.set(e.to, []);
  rev.get(e.to).push(e.from);
}

const direct = new Set();
for (const s of seeds) {
  const im = rev.get(s) || [];
  for (const f of im) direct.add(f);
}

const transitive = new Set([...seeds, ...direct]);
let frontier = [...direct];
while (frontier.length) {
  const n = frontier.pop();
  const im = rev.get(n) || [];
  for (const f of im) {
    if (!transitive.has(f)) {
      transitive.add(f);
      frontier.push(f);
    }
  }
}

const testRe = /\.(test|spec)\.(tsx?|mts|cts)$|__tests__\//;
const testFiles = [...transitive].filter((r) => testRe.test(r));

function lineEstimate(rel) {
  const p = path.join(ROOT, rel);
  try {
    const t = fs.readFileSync(p, "utf8");
    return t.split(/\r?\n/).length;
  } catch {
    return 0;
  }
}

let estLines = 0;
for (const r of transitive) estLines += lineEstimate(r);

function fileMatchesScope(rel, inv) {
  const chk = inv.check || {};
  const sc = chk.scope;
  if (typeof sc === "string" && sc.length) {
    const norm = sc.replace(/\\/g, "/").replace(/\/$/, "");
    if (rel === norm || rel.startsWith(norm + "/")) return true;
  }
  for (const raw of chk.scope_globs || []) {
    const g = String(raw).replace(/\\/g, "/");
    if (!g.includes("*")) {
      const base = g.replace(/\/$/, "");
      if (rel === g || rel.startsWith(base + "/")) return true;
      continue;
    }
    const prefix = g.split("*")[0].replace(/\/$/, "");
    if (prefix && (rel === prefix || rel.startsWith(prefix + "/"))) return true;
  }
  return false;
}

function invariantRisk(rel, inv) {
  const chk = inv.check || {};
  if (chk.type === "dependency_absent") {
    if (rel.startsWith("client/") || rel.startsWith("server/")) {
      return "MONITOR";
    }
  }
  if (fileMatchesScope(rel, inv)) return "AT_RISK";
  return null;
}

const invPath = path.join(ROOT, ".claude", "invariants.json");
let invData = { invariants: [] };
if (fs.existsSync(invPath)) {
  try {
    invData = JSON.parse(fs.readFileSync(invPath, "utf8"));
  } catch {
    invData = { invariants: [] };
  }
}
const invs = Array.isArray(invData.invariants)
  ? invData.invariants
  : Array.isArray(invData)
  ? invData
  : [];

const atRisk = [];
for (const inv of invs) {
  if (!inv || !inv.id) continue;
  let level = null;
  let reason = "";
  for (const s of seeds) {
    const r = invariantRisk(s, inv);
    if (r === "AT_RISK") {
      level = "AT_RISK";
      reason = `${s} in invariant scope`;
      break;
    }
    if (r === "MONITOR") {
      level = "MONITOR";
      reason = "client/server surface — dependency_absent relevant";
    }
  }
  if (level) {
    atRisk.push({ id: inv.id, name: inv.name || "", level, reason });
  }
}

const report = {
  ts: new Date().toISOString().replace(/\.\d{3}Z$/, "Z"),
  change: changeDesc,
  contract_delta: delta,
  blast_radius: {
    seeds,
    direct_affected: [...direct].sort(),
    transitive_affected: [...transitive].sort(),
    test_files_affected: testFiles.sort(),
    estimated_lines_review: estLines,
  },
  invariants_at_risk: atRisk,
};

const outPath = path.join(ROOT, ".claude", "simulation-report.json");
fs.mkdirSync(path.dirname(outPath), { recursive: true });
fs.writeFileSync(outPath, JSON.stringify(report, null, 2), "utf8");

function recText() {
  const lines = [];
  lines.push(`RECOMMENDATION (heuristic, not a substitute for human design):`);
  if (delta.overall === "BREAKING") {
    lines.push(`  - Prefer additive API first (optional fields), migrate callers, then tighten contracts.`);
  } else if (delta.overall === "ADDITIVE") {
    lines.push(`  - Additive surface — keep defaults backward-compatible; expand tests at boundaries.`);
  } else {
    lines.push(`  - Review transitive list and run targeted tests before merge.`);
  }
  if (atRisk.some((x) => x.level === "AT_RISK")) {
    lines.push(`  - Re-run /verify-invariants after edits; resolve AT_RISK items touching Critical surfaces.`);
  }
  return lines.join("\n");
}

console.log("[OS-SIMULATION] proposed change:", changeDesc);
console.log("");
console.log("CONTRACT DELTA:");
if (delta.details && delta.details.length) {
  for (const d of delta.details.slice(0, 20)) {
    console.log(`  ${d.symbol} (${d.kind}): ${d.delta} — ${d.note || ""}`);
  }
  if (delta.details.length > 20) console.log(`  ... (${delta.details.length} total detail rows)`);
} else {
  console.log(`  (none or skipped) overall=${delta.overall || "UNKNOWN"}`);
}
if (delta.conflicts && delta.conflicts.length) {
  for (const c of delta.conflicts) {
    console.log(`  CONFLICT: ${c.code} — ${c.message}`);
  }
}
if (delta.error) {
  console.log(`  NOTE: ${delta.error} — ${delta.message || ""}`);
}
console.log("");
console.log("BLAST RADIUS:");
console.log(`  direct:     ${direct.size} modules import seed file(s)`);
console.log(`  transitive: ${transitive.size} modules (reverse dependency closure)`);
console.log(`  tests:      ${testFiles.length} test-like files in closure`);
console.log(`  estimated:  ~${estLines} lines in affected modules (rough LOC)`);
if ([...direct].length) console.log(`  direct files: ${[...direct].slice(0, 12).join(", ")}${direct.size > 12 ? "..." : ""}`);
console.log("");
console.log("INVARIANTS AT RISK:");
if (!atRisk.length) {
  console.log("  (none matched against seeds — graph or scopes may be empty)");
} else {
  for (const x of atRisk) {
    console.log(`  ${x.id} ${x.name}: ${x.level} (${x.reason})`);
  }
}
console.log("");
console.log(recText());
NODE

exit 0
