/**
 * Semantic diff analyzer — contract deltas + heuristics (TypeScript Compiler API).
 * Usage: node semantic-diff.cjs <repoRoot> <relativeFile> [--base REF]
 * Compares git <base>:file vs worktree file (default base=HEAD).
 */
import { execSync } from "child_process";
import * as fs from "fs";
import * as path from "path";
import * as ts from "typescript";

interface Report {
  generated_at: string;
  file: string;
  base: string;
  contract_changes: string[];
  refactor: string[];
  security: string[];
}

function norm(s: string): string {
  return s.replace(/\s+/g, " ").trim().slice(0, 800);
}

function gitShow(repo: string, ref: string, rel: string): string | null {
  const spec = rel.replace(/\\/g, "/");
  try {
    return execSync(`git show ${ref}:${spec}`, {
      cwd: repo,
      encoding: "utf8",
      stdio: ["pipe", "pipe", "ignore"],
      maxBuffer: 20 * 1024 * 1024,
    });
  } catch {
    return null;
  }
}

function readWt(repo: string, rel: string): string | null {
  const p = path.join(repo, rel);
  try {
    return fs.readFileSync(p, "utf8");
  } catch {
    return null;
  }
}

function isExported(node: ts.Node): boolean {
  if (!ts.canHaveModifiers(node)) return false;
  const mods = ts.getModifiers(node);
  return mods?.some((m) => m.kind === ts.SyntaxKind.ExportKeyword) ?? false;
}

function collectContracts(sf: ts.SourceFile): Map<string, { kind: string; text: string }> {
  const m = new Map<string, { kind: string; text: string }>();
  const visit = (node: ts.Node) => {
    if (ts.isInterfaceDeclaration(node) && node.name && isExported(node)) {
      m.set(node.name.text, { kind: "interface", text: norm(node.getText(sf)) });
    }
    if (ts.isTypeAliasDeclaration(node) && node.name && isExported(node)) {
      m.set(node.name.text, { kind: "type", text: norm(node.getText(sf)) });
    }
    if (ts.isFunctionDeclaration(node) && node.name && isExported(node)) {
      const sig = node.getText(sf);
      m.set(node.name.text, { kind: "function", text: norm(sig) });
    }
    if (ts.isClassDeclaration(node) && node.name && isExported(node)) {
      m.set(node.name.text, { kind: "class", text: norm(node.getText(sf)) });
    }
    if (ts.isEnumDeclaration(node) && node.name && isExported(node)) {
      m.set(node.name.text, { kind: "enum", text: norm(node.getText(sf)) });
    }
    if (ts.isVariableStatement(node) && isExported(node)) {
      for (const d of node.declarationList.declarations) {
        if (ts.isIdentifier(d.name)) {
          m.set(d.name.text, { kind: "const", text: norm(d.getText(sf)) });
        }
      }
    }
    ts.forEachChild(node, visit);
  };
  visit(sf);
  if (sf.statements.some((s) => ts.isExportDeclaration(s) && s.exportClause)) {
    for (const st of sf.statements) {
      if (!ts.isExportDeclaration(st) || !st.exportClause) continue;
      if (ts.isNamedExports(st.exportClause)) {
        for (const el of st.exportClause.elements) {
          const nm = el.name.text;
          if (!m.has(nm)) m.set(nm, { kind: "re-export", text: `export { ${nm} }` });
        }
      }
    }
  }
  return m;
}

function parseSf(filePath: string, text: string): ts.SourceFile {
  const kind = filePath.endsWith(".tsx")
    ? ts.ScriptKind.TSX
    : filePath.endsWith(".ts")
      ? ts.ScriptKind.TS
      : ts.ScriptKind.TS;
  return ts.createSourceFile(filePath, text || "", ts.ScriptTarget.Latest, true, kind);
}

function diffContracts(
  before: Map<string, { kind: string; text: string }>,
  after: Map<string, { kind: string; text: string }>
): string[] {
  const lines: string[] = [];
  const all = new Set([...before.keys(), ...after.keys()]);
  for (const k of [...all].sort()) {
    const o = before.get(k);
    const n = after.get(k);
    if (!o && n) {
      lines.push(`  ADDED export \`${k}\` (${n.kind})`);
    } else if (o && !n) {
      lines.push(`  REMOVED export \`${k}\` (${o.kind}) — breaking unless unused`);
    } else if (o && n && o.text !== n.text) {
      lines.push(`  CHANGED \`${k}\` (${o.kind}):`);
      lines.push(`    Before: ${o.text.slice(0, 220)}${o.text.length > 220 ? "…" : ""}`);
      lines.push(`    After:  ${n.text.slice(0, 220)}${n.text.length > 220 ? "…" : ""}`);
      const additive =
        n.text.includes("?:") ||
        n.text.includes("? ") ||
        (o.kind === "function" &&
          n.kind === "function" &&
          n.text.split(",").length > o.text.split(",").length);
      lines.push(
        `    Impact: ${additive ? "likely additive / widened surface — verify backwards compatibility" : "possible breaking change — verify all callers"}`
      );
    }
  }
  return lines;
}

function countFunctions(sf: ts.SourceFile): number {
  let n = 0;
  const visit = (node: ts.Node) => {
    if (ts.isFunctionDeclaration(node) && node.name) n++;
    if (ts.isFunctionExpression(node)) n++;
    if (ts.isArrowFunction(node)) n++;
    ts.forEachChild(node, visit);
  };
  visit(sf);
  return n;
}

function refactorAnalysis(
  beforeText: string,
  afterText: string,
  beforeSf: ts.SourceFile,
  afterSf: ts.SourceFile,
  contractsChanged: boolean
): string[] {
  const out: string[] = [];
  if (contractsChanged) return out;
  const fb = countFunctions(beforeSf);
  const fa = countFunctions(afterSf);
  const lenRatio = afterText.length / Math.max(1, beforeText.length);
  if (fa > fb && lenRatio > 0.85 && lenRatio < 1.35) {
    out.push(`  Structural change: ${fa - fb} additional function(s) in module (possible extraction)`);
    out.push(`  Behavioral equivalence: LIKELY (exported contracts unchanged; internal structure shifted)`);
    out.push(
      `  Verification gap: new inner helpers may lack direct unit tests — add tests around extracted logic`
    );
    out.push(`  Recommendation: add focused unit tests before merging`);
  } else if (lenRatio < 1.08 && lenRatio > 0.92 && fa === fb) {
    out.push(`  Structural change: minor edits with same function count`);
    out.push(`  Behavioral equivalence: UNKNOWN — require tests / review`);
  }
  return out;
}

function securitySemanticScan(beforeText: string, afterText: string, afterSf: ts.SourceFile): string[] {
  const out: string[] = [];
  const roleStrict = /\.role\s*===\s*['"]admin['"]|===\s*['"]admin['"]\s*\)\s*&&\s*\(?\s*\w*\.role\b/;
  const rolesIncludes =
    /\.roles\.includes\s*\(\s*['"]admin['"]\s*\)|\broles\b[^\n]{0,40}includes\s*\(\s*['"]admin['"]/;

  if (roleStrict.test(beforeText) && rolesIncludes.test(afterText)) {
    out.push(`  Pattern: scalar role equality → array membership check`);
    out.push(`  Semantic difference:`);
    out.push(`    Before: exact string match on a single role field`);
    out.push(`    After:  array includes — if roles is undefined, includes() throws (different failure mode)`);
    out.push(`  This is a security boundary change — requires Opus review`);
  }

  const seenDyn = new Set<string>();
  const visit = (node: ts.Node) => {
    if (ts.isCallExpression(node)) {
      const t = node.getText(afterSf);
      if (/eval\s*\(|new\s+Function\s*\(/.test(t)) {
        const key = t.slice(0, 80);
        if (!seenDyn.has(key)) {
          seenDyn.add(key);
          out.push(`  Dynamic code execution detected: ${t.slice(0, 120)} — high risk`);
        }
      }
    }
    ts.forEachChild(node, visit);
  };
  visit(afterSf);
  return out;
}

function main() {
  const argv = process.argv.slice(2);
  let base = "HEAD";
  const rest: string[] = [];
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--base" && argv[i + 1]) {
      base = argv[i + 1];
      i++;
    } else {
      rest.push(argv[i]);
    }
  }
  const repo = path.resolve(rest[0] || process.cwd());
  const rel = (rest[1] || "").replace(/\\/g, "/");
  if (!rel) {
    console.log("[OS-SEMANTIC-DIFF] usage: node semantic-diff.cjs <repo> <file.ts> [--base REF]");
    process.exit(0);
  }

  const ext = path.extname(rel).toLowerCase();
  if (![".ts", ".tsx", ".mts", ".cts"].includes(ext)) {
    console.log(`[OS-SEMANTIC-DIFF] ${rel}`);
    console.log(`  skip: only TypeScript sources are analyzed`);
    process.exit(0);
  }

  const beforeText = gitShow(repo, base, rel) || "";
  const afterText = readWt(repo, rel) ?? gitShow(repo, "HEAD", rel) ?? "";

  const beforeSf = parseSf(rel, beforeText);
  const afterSf = parseSf(rel, afterText);
  const beforeMap = collectContracts(beforeSf);
  const afterMap = collectContracts(afterSf);
  const contractLines = diffContracts(beforeMap, afterMap);
  const contractsChanged = contractLines.length > 0;

  console.log(`[OS-SEMANTIC-DIFF] ${rel} (${base} → worktree)`);

  if (contractsChanged) {
    console.log("CONTRACT CHANGE DETECTED:");
    for (const ln of contractLines) console.log(ln);
  } else {
    console.log("CONTRACT CHANGE DETECTED: (none — exported surface unchanged)");
  }

  const refLines = refactorAnalysis(beforeText, afterText, beforeSf, afterSf, contractsChanged);
  if (refLines.length) {
    console.log(`REFACTOR ANALYSIS: ${rel}`);
    for (const ln of refLines) console.log(ln);
  }

  const sec = securitySemanticScan(beforeText, afterText, afterSf);
  if (sec.length) {
    console.log("SECURITY SEMANTIC CHANGE:");
    for (const ln of sec) console.log(ln);
  }

  const report: Report = {
    generated_at: new Date().toISOString(),
    file: rel,
    base,
    contract_changes: contractLines,
    refactor: refLines,
    security: sec,
  };
  const outDir = path.join(repo, ".claude");
  try {
    fs.mkdirSync(outDir, { recursive: true });
    fs.writeFileSync(
      path.join(outDir, "semantic-diff-report.json"),
      JSON.stringify(report, null, 2),
      "utf8"
    );
  } catch {
    /* ignore */
  }
  console.log(`  wrote .claude/semantic-diff-report.json`);
}

main();
