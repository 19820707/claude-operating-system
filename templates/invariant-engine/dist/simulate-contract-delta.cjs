#!/usr/bin/env node
/**
 * Contract delta simulation — compares exported API surface between two in-memory
 * snapshots (baseline file vs proposed file). No writes to the repo baseline path.
 * Requires `typescript` resolvable from the consumer project (npm i -D typescript).
 * Exit 0 always; errors on stderr as JSON field.
 */
"use strict";

const fs = require("fs");
const path = require("path");

function loadTs() {
  const beside = path.join(__dirname, "..", "node_modules", "typescript");
  if (fs.existsSync(path.join(beside, "package.json"))) {
    return require(beside);
  }
  const roots = [
    process.cwd(),
    path.join(process.cwd(), "templates", "invariant-engine"),
  ];
  for (const r of roots) {
    try {
      const mod = path.join(r, "node_modules", "typescript");
      if (fs.existsSync(path.join(mod, "lib", "typescript.js"))) {
        return require(mod);
      }
    } catch (_) {
      /* continue */
    }
  }
  try {
    return require("typescript");
  } catch (_) {
    return null;
  }
}

function hasExportModifier(ts, node) {
  const mods = node.modifiers;
  if (!mods) return false;
  return mods.some((m) => m.kind === ts.SyntaxKind.ExportKeyword);
}

function isExported(ts, node) {
  if (hasExportModifier(ts, node)) return true;
  let p = node.parent;
  while (p) {
    if (ts.isSourceFile(p)) break;
    if (
      (ts.isModuleDeclaration(p) || ts.isNamespaceDeclaration?.(p)) &&
      hasExportModifier(ts, p)
    )
      return true;
    p = p.parent;
  }
  return false;
}

function paramSummary(ts, sf, params) {
  return params.map((p) => {
    const optional = !!p.questionToken || !!p.initializer;
    const name = p.name ? p.name.getText(sf) : "?";
    return { name, optional, dotted: !!p.dotDotDotToken };
  });
}

function collectFromSourceFile(ts, sf) {
  const functions = [];
  const interfaces = [];
  const typeAliases = [];

  function visit(node) {
    if (ts.isFunctionDeclaration(node) && node.name && isExported(ts, node)) {
      const name = node.name.text;
      const params = paramSummary(ts, sf, node.parameters);
      functions.push({
        kind: "function",
        name,
        async: !!node.modifiers?.some(
          (m) => m.kind === ts.SyntaxKind.AsyncKeyword
        ),
        params,
        rawSignature: node.getText(sf).split(/\{|;$/)[0].trim().slice(0, 400),
      });
    }
    if (ts.isInterfaceDeclaration(node) && isExported(ts, node)) {
      interfaces.push({
        kind: "interface",
        name: node.name.text,
        raw: node.getText(sf).slice(0, 800),
      });
    }
    if (ts.isTypeAliasDeclaration(node) && isExported(ts, node)) {
      typeAliases.push({
        kind: "type",
        name: node.name.text,
        raw: node.getText(sf).slice(0, 400),
      });
    }
    ts.forEachChild(node, visit);
  }

  visit(sf);
  return { functions, interfaces, typeAliases, fileName: sf.fileName };
}

function parseFile(ts, absPath) {
  const text = fs.readFileSync(absPath, "utf8");
  const sf = ts.createSourceFile(
    absPath,
    text,
    ts.ScriptTarget.Latest,
    true,
    absPath.endsWith(".tsx") ? ts.ScriptKind.TSX : ts.ScriptKind.TS
  );
  return collectFromSourceFile(ts, sf);
}

function classifyParamChange(beforeParams, afterParams) {
  const req = (ps) => ps.filter((p) => !p.optional && !p.dotted);
  const br = req(beforeParams);
  const ar = req(afterParams);
  if (ar.length !== br.length) return "BREAKING";
  for (let i = 0; i < ar.length; i++) {
    if (!br[i] || br[i].name !== ar[i].name) return "BREAKING";
  }
  if (afterParams.length > beforeParams.length) {
    const tail = afterParams.slice(beforeParams.length);
    if (tail.length && tail.every((p) => p.optional)) return "ADDITIVE";
  }
  if (JSON.stringify(beforeParams) === JSON.stringify(afterParams)) return "NEUTRAL";
  const relaxed = beforeParams.some(
    (p, i) => p && !p.optional && afterParams[i] && afterParams[i].optional
  );
  if (relaxed) return "ADDITIVE";
  return "NEUTRAL";
}

function compareContracts(ts, base, prop) {
  const details = [];
  const conflicts = [];
  let worst = "NEUTRAL";

  const rank = (s) => (s === "BREAKING" ? 3 : s === "ADDITIVE" ? 2 : 1);
  const bump = (s) => {
    if (rank(s) > rank(worst)) worst = s;
  };

  const bf = new Map(base.functions.map((f) => [f.name, f]));
  const pf = new Map(prop.functions.map((f) => [f.name, f]));

  for (const [name, after] of pf) {
    const before = bf.get(name);
    if (!before) {
      details.push({
        symbol: name,
        kind: "function",
        delta: "ADDITIVE",
        note: "new exported function",
      });
      bump("ADDITIVE");
      continue;
    }
    const d = classifyParamChange(before.params, after.params);
    details.push({
      symbol: name,
      kind: "function",
      delta: d,
      note: `${name}() parameter shape changed`,
      before: before.params,
      after: after.params,
    });
    bump(d);
  }
  for (const [name, before] of bf) {
    if (!pf.has(name)) {
      details.push({
        symbol: name,
        kind: "function",
        delta: "BREAKING",
        note: "removed exported function",
      });
      bump("BREAKING");
    }
  }

  const bi = new Map(base.interfaces.map((x) => [x.name, x]));
  const pi = new Map(prop.interfaces.map((x) => [x.name, x]));
  for (const [name, after] of pi) {
    const before = bi.get(name);
    if (!before) {
      details.push({
        symbol: name,
        kind: "interface",
        delta: "ADDITIVE",
        note: "new exported interface",
      });
      bump("ADDITIVE");
    } else if (before.raw !== after.raw) {
      details.push({
        symbol: name,
        kind: "interface",
        delta: "NEUTRAL",
        note: "interface body changed — review required fields manually",
      });
      bump("NEUTRAL");
    }
  }
  for (const [name] of bi) {
    if (!pi.has(name)) {
      details.push({
        symbol: name,
        kind: "interface",
        delta: "BREAKING",
        note: "removed exported interface",
      });
      bump("BREAKING");
    }
  }

  const bt = new Map(base.typeAliases.map((x) => [x.name, x]));
  const pt = new Map(prop.typeAliases.map((x) => [x.name, x]));
  for (const [name, after] of pt) {
    if (!bt.has(name)) {
      details.push({
        symbol: name,
        kind: "type",
        delta: "ADDITIVE",
        note: "new exported type alias",
      });
      bump("ADDITIVE");
    } else if (bt.get(name).raw !== after.raw) {
      details.push({
        symbol: name,
        kind: "type",
        delta: "NEUTRAL",
        note: "type alias definition changed",
      });
      bump("NEUTRAL");
    }
  }
  for (const [name] of bt) {
    if (!pt.has(name)) {
      details.push({
        symbol: name,
        kind: "type",
        delta: "BREAKING",
        note: "removed exported type alias",
      });
      bump("BREAKING");
    }
  }

  const funcDeltas = details.filter((d) => d.kind === "function");
  const hasBreakingFn = funcDeltas.some((d) => d.delta === "BREAKING");
  const hasAdditiveFn = funcDeltas.some((d) => d.delta === "ADDITIVE");
  if (hasBreakingFn && hasAdditiveFn) {
    conflicts.push({
      code: "MIXED_API_CHANGE",
      message:
        "Breaking and additive function changes both present — sequence rollout (optional first, then required) may reduce blast radius",
    });
  }

  return { overall: worst, details, conflicts };
}

function parseArgs(argv) {
  const out = { baseline: null, proposed: null, json: false };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--baseline") out.baseline = argv[++i];
    else if (a === "--proposed") out.proposed = argv[++i];
    else if (a === "--json") out.json = true;
  }
  return out;
}

function main() {
  const args = parseArgs(process.argv);
  const ts = loadTs();
  if (!ts) {
    const err = {
      error: "typescript_not_found",
      message:
        "Install devDependency: npm i -D typescript (or run from claude-operating-system with templates/invariant-engine/node_modules)",
      overall: "UNKNOWN",
    };
    console.log(JSON.stringify(err, null, 2));
    process.exitCode = 0;
    return;
  }
  if (!args.baseline || !args.proposed) {
    const err = {
      error: "usage",
      message:
        "simulate-contract-delta.cjs --baseline <path> --proposed <path> [--json]",
      overall: "UNKNOWN",
    };
    console.log(JSON.stringify(err, null, 2));
    return;
  }
  const root = process.cwd();
  const bAbs = path.isAbsolute(args.baseline)
    ? args.baseline
    : path.join(root, args.baseline);
  const pAbs = path.isAbsolute(args.proposed)
    ? args.proposed
    : path.join(root, args.proposed);
  if (!fs.existsSync(bAbs) || !fs.existsSync(pAbs)) {
    console.log(
      JSON.stringify(
        {
          error: "file_not_found",
          baseline: bAbs,
          proposed: pAbs,
          overall: "UNKNOWN",
        },
        null,
        2
      )
    );
    return;
  }
  const base = parseFile(ts, bAbs);
  const prop = parseFile(ts, pAbs);
  const result = compareContracts(ts, base, prop);
  result.baseline = path.relative(root, bAbs).split(path.sep).join("/");
  result.proposed = path.relative(root, pAbs).split(path.sep).join("/");
  result.contract_version = 1;
  console.log(JSON.stringify(result, null, args.json ? 2 : 0));
}

main();
