#!/usr/bin/env bash
# Build / query knowledge graph from source (Node). Non-blocking; exit 0; LF-only.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

if ! command -v node >/dev/null 2>&1; then
  echo "[OS-KNOWLEDGE-GRAPH] skip: node not available"
  exit 0
fi

export KG_REPO_ROOT="$REPO_ROOT"
export KG_ARGS="$*"

node <<'NODE'
"use strict";

const fs = require("fs");
const path = require("path");

const ROOT = process.env.KG_REPO_ROOT || process.cwd();
const args = (process.env.KG_ARGS || "")
  .trim()
  .split(/\s+/)
  .filter((x) => x.length > 0);

const SKIP = new Set([
  "node_modules", "dist", ".git", ".claude", ".next", "build", "coverage",
  ".turbo", "vendor", ".local", "__pycache__",
]);

const RISK_PATTERNS = [
  ["AUTH", /jwt|jsonwebtoken|passport\.authenticate|express-session|connect-pg-simple/gi],
  ["BILLING", /stripe|paymentIntent|subscription|billing/gi],
  ["SECRETS", /process\.env\.(SECRET|KEY|TOKEN|PASSWORD|STRIPE|JWT)/gi],
  ["MIGRATE", /drizzle.*push|migrate\(\)|ALTER\s+TABLE|DROP\s+TABLE/gi],
];

function shouldSkipDir(name) {
  return SKIP.has(name);
}

function walkFiles(dir, acc) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const ent of entries) {
    if (ent.name.startsWith(".")) continue;
    const full = path.join(dir, ent.name);
    const rel = path.relative(ROOT, full).split(path.sep).join("/");
    if (ent.isDirectory()) {
      if (shouldSkipDir(ent.name)) continue;
      walkFiles(full, acc);
    } else if (/\.(ts|tsx)$/.test(ent.name)) {
      acc.push({ full, rel });
    }
  }
}

function read(rel) {
  try {
    return fs.readFileSync(path.join(ROOT, rel), "utf8");
  } catch {
    return "";
  }
}

function extractImports(text) {
  const edges = [];
  const re = /^(?:import|export)\s+[^;]*?\s+from\s+["']([^"']+)["']/gm;
  let m;
  while ((m = re.exec(text))) {
    const spec = m[1];
    if (spec.startsWith(".") || spec.startsWith("@/")) edges.push(spec);
  }
  const re2 = /^import\s+["']([^"']+)["']/gm;
  while ((m = re2.exec(text))) edges.push(m[1]);
  return edges;
}

function resolveImport(fromFile, spec) {
  if (!spec || spec.startsWith("@")) return null;
  if (!spec.startsWith(".")) return null;
  const base = path.dirname(fromFile);
  let cand = path.normalize(path.join(base, spec));
  const exts = ["", ".ts", ".tsx", "/index.ts", "/index.tsx"];
  for (const e of exts) {
    const p = cand + e;
    if (fs.existsSync(p) && fs.statSync(p).isFile()) {
      return path.relative(ROOT, p).split(path.sep).join("/");
    }
  }
  return null;
}

function extractExports(text) {
  const out = [];
  const re =
    /^export\s+(?:async\s+)?(?:function|class|const|type|interface)\s+([A-Za-z0-9_]+)/gm;
  let m;
  while ((m = re.exec(text))) out.push(m[1]);
  return out;
}

function riskAttrs(text) {
  const patterns = [];
  let score = 0;
  for (const [name, rx] of RISK_PATTERNS) {
    rx.lastIndex = 0;
    if (rx.test(text)) {
      patterns.push(name);
      score += 2;
    }
  }
  let level = "LOW";
  if (score >= 6) level = "HIGH";
  else if (score >= 2) level = "MEDIUM";
  return { patterns, score, level };
}

function layer(rel) {
  if (rel.startsWith("client/")) return "client";
  if (rel.startsWith("server/")) return "server";
  if (rel.startsWith("shared/")) return "shared";
  if (rel.startsWith("src/")) return "src";
  return "other";
}

function main() {
  const mode = args[0] || "--help";
  if (mode === "--violations") {
    const kgPath = path.join(ROOT, ".claude", "knowledge-graph.json");
    if (!fs.existsSync(kgPath)) {
      console.log("[OS-KNOWLEDGE-GRAPH] boundary violations: (no graph — run --build)");
      return;
    }
    const kg = JSON.parse(fs.readFileSync(kgPath, "utf8"));
    const bv = kg.boundary_violations || [];
    console.log("[OS-KNOWLEDGE-GRAPH] boundary violations:");
    if (!bv.length) console.log("  (none)");
    else bv.forEach((v) => console.log(`  ${v}`));
    return;
  }

  if (mode === "--query") {
    const target = args[1];
    if (!target) {
      console.log("[OS-KNOWLEDGE-GRAPH] --query requires filepath");
      return;
    }
    const kgPath = path.join(ROOT, ".claude", "knowledge-graph.json");
    if (!fs.existsSync(kgPath)) {
      console.log("[OS-KNOWLEDGE-GRAPH] no graph — run --build");
      return;
    }
    const kg = JSON.parse(fs.readFileSync(kgPath, "utf8"));
    const nodes = kg.nodes || {};
    const n = nodes[target.replace(/\\/g, "/")];
    if (!n) {
      console.log(`[OS-KNOWLEDGE-GRAPH] unknown module: ${target}`);
      return;
    }
    console.log(`module: ${target}`);
    console.log(`exports: ${(n.contracts && n.contracts.exports) || []}`);
    console.log(`imports_from: ${(n.contracts && n.contracts.imports_from) || []}`);
    console.log(`risk:`, n.risk_attributes || {});
    return;
  }

  if (mode !== "--build" && mode !== "--subgraph") {
    console.log(
      "usage: knowledge-graph.sh --build | --subgraph <file> | --violations | --query <file>"
    );
    return;
  }

  const files = [];
  walkFiles(ROOT, files);

  const nodes = {};
  const edges = [];
  const boundaryViolations = [];

  const complexityPath = path.join(ROOT, ".claude", "complexity-map.json");
  let complexity = {};
  if (fs.existsSync(complexityPath)) {
    try {
      complexity = JSON.parse(fs.readFileSync(complexityPath, "utf8"));
    } catch {}
  }

  for (const { full, rel } of files) {
    const text = read(rel);
    const imports = extractImports(text);
    const resolved = [];
    for (const spec of imports) {
      const to = resolveImport(full, spec);
      if (to) {
        resolved.push(to);
        edges.push({
          from: rel,
          to,
          type: "contract_dependency",
          symbol: spec,
        });
        const lf = layer(rel);
        const lt = layer(to);
        if (
          (lf === "client" && lt === "server") ||
          (lf === "server" && lt === "client")
        ) {
          if (!(lf === "shared" || lt === "shared")) {
            boundaryViolations.push(
              `${rel} imports ${to} (${lf}→${lt})`
            );
          }
        }
      }
    }
    const exports = extractExports(text);
    const risk = riskAttrs(text);
    let score = risk.score;
    if (complexity[rel] && typeof complexity[rel].score === "number") {
      score += complexity[rel].score;
    }
    nodes[rel] = {
      type: "module",
      contracts: { exports, imports_from: resolved },
      risk_attributes: { ...risk, score },
      boundary_violations: [],
    };
  }

  const builtAt = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
  const kg = {
    built_at: builtAt,
    nodes,
    edges,
    boundary_violations: boundaryViolations,
    open_questions: [],
  };

  if (mode === "--build") {
    const out = path.join(ROOT, ".claude", "knowledge-graph.json");
    fs.mkdirSync(path.dirname(out), { recursive: true });
    fs.writeFileSync(out, JSON.stringify(kg, null, 2), "utf8");
    console.log(
      `[OS-KNOWLEDGE-GRAPH] built: ${Object.keys(nodes).length} nodes, ${edges.length} edges, ${boundaryViolations.length} violations`
    );
    return;
  }

  const target = args[1];
  if (!target) {
    console.log("[OS-KNOWLEDGE-GRAPH] --subgraph requires filepath");
    return;
  }
  const t = target.replace(/\\/g, "/");
  const nset = new Set([t]);
  for (const e of edges) {
    if (e.from === t) nset.add(e.to);
    if (e.to === t) nset.add(e.from);
  }
  const subNodes = {};
  for (const k of nset) {
    if (nodes[k]) subNodes[k] = nodes[k];
  }
  const subEdges = edges.filter((e) => nset.has(e.from) && nset.has(e.to));
  const subBv = boundaryViolations.filter(
    (v) =>
      v.includes(t) ||
      [...nset].some((n) => typeof v === "string" && v.includes(n))
  );
  const sub = {
    built_at: builtAt,
    center: t,
    nodes: subNodes,
    edges: subEdges,
    boundary_violations: subBv,
    open_questions: [],
  };
  const base = path.basename(t).replace(/[^a-zA-Z0-9_.-]/g, "_");
  const spath = path.join(ROOT, ".claude", `subgraph-${base}.json`);
  fs.mkdirSync(path.dirname(spath), { recursive: true });
  fs.writeFileSync(spath, JSON.stringify(sub, null, 2), "utf8");
  console.log(
    `[OS-KNOWLEDGE-GRAPH] subgraph: ${Object.keys(subNodes).length} nodes for ${t}`
  );
}

try {
  main();
} catch (e) {
  console.error("[OS-KNOWLEDGE-GRAPH] ERROR:", e && e.message ? e.message : e);
}
NODE

exit 0
