/**
 * OS Invariant Verification Engine — TypeScript Compiler API (no shell grep).
 * Invoked: node dist/invariant-engine.cjs <repoRoot> [invariantsDir]
 */
import * as fs from "fs";
import * as path from "path";
import * as ts from "typescript";

type Severity = "CRITICAL" | "WARN" | "INFO";

interface Violation {
  file: string;
  line: number;
  col: number;
  message: string;
}

interface InvariantResult {
  id: string;
  name: string;
  status: "PASS" | "FAIL" | "WARN" | "SKIP";
  summary: string;
  violations: Violation[];
  heuristic_ref?: string;
  severity: Severity;
}

type Check =
  | PatternCountCheck
  | FailClosedSwitchCheck
  | SensitiveLoggerCheck
  | MissingPatternCheck;

interface InvariantSpec {
  id: string;
  name: string;
  description: string;
  check: Check;
  violation_severity: Severity;
  heuristic_ref?: string;
}

interface PatternCountCheck {
  type: "pattern_count";
  pattern: string;
  scope: string;
  operator: "<=" | ">=" | "==" | "!=";
  expected: number;
  aggregate?: "total" | "per_file_max" | "per_file_min";
  match_extensions?: string[];
}

interface FailClosedSwitchCheck {
  type: "fail_closed_switch";
  target_globs: string[];
}

interface SensitiveLoggerCheck {
  type: "sensitive_logger";
  scope: string;
  sink_substrings?: string[];
  forbidden_arg_substrings?: string[];
}

interface MissingPatternCheck {
  type: "missing_pattern";
  scope: string;
  must_contain: string | string[];
  path_substring?: string;
  extensions?: string[];
  sample_limit?: number;
}

const DEFAULT_EXT = [".ts", ".tsx", ".mts", ".cts"];
const SKIP_DIRS = new Set([
  "node_modules",
  ".git",
  "dist",
  "build",
  ".next",
  "coverage",
  ".claude",
  ".turbo",
  "vendor",
]);

function posix(p: string): string {
  return p.split(path.sep).join("/");
}

function listFilesUnderScope(
  repo: string,
  scopeDir: string,
  extensions: string[]
): string[] {
  const root = path.join(repo, scopeDir);
  if (!fs.existsSync(root)) return [];
  const out: string[] = [];
  const walk = (dir: string) => {
    let entries: fs.Dirent[] = [];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      if (e.isDirectory()) {
        if (SKIP_DIRS.has(e.name)) continue;
        walk(path.join(dir, e.name));
      } else if (e.isFile()) {
        const ext = path.extname(e.name);
        if (extensions.includes(ext)) {
          out.push(path.join(dir, e.name));
        }
      }
    }
  };
  walk(root);
  return out.sort();
}

function matchGlob(relPosix: string, pattern: string): boolean {
  const esc = (s: string) => s.replace(/[.+^${}()|[\]\\]/g, "\\$&");
  let p = pattern.replace(/\\/g, "/");
  if (!p.includes("*")) {
    return relPosix === p || relPosix.endsWith("/" + p);
  }
  const parts = p.split("**");
  if (parts.length === 1) {
    const rx = "^" + p.split("*").map(esc).join("[^/]*") + "$";
    return new RegExp(rx, "i").test(relPosix);
  }
  const head = parts[0].replace(/\*/g, "[^/]*");
  const tail = parts.slice(1).join("**").replace(/\*/g, ".*");
  const rx = "^" + head + ".*" + tail + "$";
  return new RegExp(rx, "i").test(relPosix);
}

function loadSpecs(invDir: string): InvariantSpec[] {
  if (!fs.existsSync(invDir)) return [];
  const acc: InvariantSpec[] = [];
  for (const name of fs.readdirSync(invDir)) {
    if (!name.endsWith(".json")) continue;
    const fp = path.join(invDir, name);
    let raw: unknown;
    try {
      raw = JSON.parse(fs.readFileSync(fp, "utf8"));
    } catch {
      continue;
    }
    if (Array.isArray(raw)) {
      for (const x of raw) {
        if (isSpec(x)) acc.push(x);
      }
    } else if (raw && typeof raw === "object" && Array.isArray((raw as { invariants?: unknown }).invariants)) {
      for (const x of (raw as { invariants: unknown[] }).invariants) {
        if (isSpec(x)) acc.push(x);
      }
    }
  }
  return acc;
}

function isSpec(x: unknown): x is InvariantSpec {
  if (!x || typeof x !== "object") return false;
  const o = x as Record<string, unknown>;
  return typeof o.id === "string" && typeof o.check === "object" && o.check !== null;
}

function lineCol(sf: ts.SourceFile, pos: number): { line: number; col: number } {
  const lc = sf.getLineAndCharacterOfPosition(pos);
  return { line: lc.line + 1, col: lc.character + 1 };
}

function checkPatternCount(
  repo: string,
  inv: InvariantSpec,
  c: PatternCountCheck
): InvariantResult {
  const exts = c.match_extensions?.length ? c.match_extensions : DEFAULT_EXT;
  const files = listFilesUnderScope(repo, c.scope, exts);
  let rx: RegExp;
  try {
    rx = new RegExp(c.pattern, "g");
  } catch {
    return {
      ...baseResult(inv, "SKIP"),
      summary: `invalid regex: ${c.pattern}`,
    };
  }
  const perFile: number[] = [];
  const locs: Violation[] = [];
  for (const fp of files) {
    const text = fs.readFileSync(fp, "utf8");
    let n = 0;
    let m: RegExpExecArray | null;
    const r2 = new RegExp(c.pattern, "g");
    while ((m = r2.exec(text)) !== null) {
      n++;
      const sf = ts.createSourceFile(fp, text, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
      const pos = m.index;
      const { line, col } = lineCol(sf, pos);
      locs.push({
        file: posix(path.relative(repo, fp)),
        line,
        col,
        message: `match: ${m[0].slice(0, 80)}`,
      });
    }
    perFile.push(n);
  }
  const total = perFile.reduce((a, b) => a + b, 0);
  const maxF = perFile.length ? Math.max(...perFile) : 0;
  const minF = perFile.length ? Math.min(...perFile) : 0;
  const agg = c.aggregate || "total";
  let value = total;
  if (agg === "per_file_max") value = maxF;
  if (agg === "per_file_min") value = minF;
  const ok = compare(value, c.operator, c.expected);
  const status: InvariantResult["status"] = ok ? "PASS" : inv.violation_severity === "WARN" ? "WARN" : "FAIL";
  const summary = ok
    ? `${agg}=${value} (${files.length} files)`
    : `${agg}=${value} violates ${c.operator} ${c.expected}`;
  const violations = ok ? [] : locs.slice(0, 24);
  return { ...baseResult(inv, status), summary, violations };
}

function compare(v: number, op: string, exp: number): boolean {
  switch (op) {
    case "<=":
      return v <= exp;
    case ">=":
      return v >= exp;
    case "==":
      return v === exp;
    case "!=":
      return v !== exp;
    default:
      return true;
  }
}

function baseResult(inv: InvariantSpec, status: InvariantResult["status"]): InvariantResult {
  return {
    id: inv.id,
    name: inv.name,
    status,
    summary: "",
    violations: [],
    heuristic_ref: inv.heuristic_ref,
    severity: inv.violation_severity,
  };
}

function defaultClauseDenies(sf: ts.SourceFile, def: ts.DefaultClause): boolean {
  const t = def.getText(sf);
  if (/return\s+false\b/.test(t)) return true;
  if (/allowed\s*:\s*false/.test(t)) return true;
  if (/deny\s*\(/.test(t) && /return/.test(t)) return true;
  return false;
}

function checkFailClosedSwitch(
  repo: string,
  inv: InvariantSpec,
  c: FailClosedSwitchCheck
): InvariantResult {
  const violations: Violation[] = [];
  const roots = ["server", "client", "shared", "src"];
  for (const r of roots) {
    const base = path.join(repo, r);
    if (!fs.existsSync(base)) continue;
    const files = listFilesUnderScope(repo, r, DEFAULT_EXT);
    for (const fp of files) {
      const rel = posix(path.relative(repo, fp));
      if (!c.target_globs.some((g) => matchGlob(rel, g))) continue;
      const text = fs.readFileSync(fp, "utf8");
      const sf = ts.createSourceFile(fp, text, ts.ScriptTarget.Latest, true);
      const visit = (node: ts.Node) => {
        if (ts.isSwitchStatement(node)) {
          const def = node.caseBlock.clauses.find(ts.isDefaultClause) as
            | ts.DefaultClause
            | undefined;
          const pos = node.getStart(sf);
          const { line, col } = lineCol(sf, pos);
          if (!def) {
            violations.push({
              file: rel,
              line,
              col,
              message: "SwitchStatement without default — not fail-closed",
            });
          } else if (!defaultClauseDenies(sf, def)) {
            violations.push({
              file: rel,
              line,
              col,
              message: "default clause does not explicitly deny (expect return false or allowed: false)",
            });
          }
        }
        ts.forEachChild(node, visit);
      };
      visit(sf);
    }
  }
  const status =
    violations.length === 0 ? "PASS" : inv.violation_severity === "WARN" ? "WARN" : "FAIL";
  return {
    ...baseResult(inv, status),
    summary:
      violations.length === 0
        ? "all matching switches have explicit deny default"
        : `${violations.length} switch(es) need review`,
    violations,
  };
}

function calleeText(expr: ts.LeftHandSideExpression, sf: ts.SourceFile): string {
  if (ts.isPropertyAccessExpression(expr)) {
    return expr.expression.getText(sf) + "." + expr.name.getText(sf);
  }
  if (ts.isIdentifier(expr)) return expr.text;
  return expr.getText(sf);
}

function checkSensitiveLogger(
  repo: string,
  inv: InvariantSpec,
  c: SensitiveLoggerCheck
): InvariantResult {
  const sinks = c.sink_substrings || [
    "console.log",
    "console.debug",
    "console.info",
    "logger.debug",
    "logger.info",
  ];
  const bad = (c.forbidden_arg_substrings || [
    "password",
    "secret",
    "token",
    "apiKey",
    "api_key",
    "authorization",
  ]).map((s) => s.toLowerCase());
  const files = listFilesUnderScope(repo, c.scope, DEFAULT_EXT);
  const violations: Violation[] = [];
  for (const fp of files) {
    const text = fs.readFileSync(fp, "utf8");
    const sf = ts.createSourceFile(fp, text, ts.ScriptTarget.Latest, true);
    const visit = (node: ts.Node) => {
      if (ts.isCallExpression(node)) {
        const ct = calleeText(node.expression as ts.LeftHandSideExpression, sf);
        const hitSink = sinks.some((s) => ct.includes(s.replace(/\s/g, "")) || ct.endsWith(s));
        if (!hitSink) {
          ts.forEachChild(node, visit);
          return;
        }
        const argText = node.arguments.map((a) => a.getText(sf)).join(" ").toLowerCase();
        for (const b of bad) {
          if (argText.includes(b)) {
            const pos = node.getStart(sf);
            const { line, col } = lineCol(sf, pos);
            violations.push({
              file: posix(path.relative(repo, fp)),
              line,
              col,
              message: `sensitive data may leak via ${ct} (arg matches "${b}")`,
            });
            break;
          }
        }
      }
      ts.forEachChild(node, visit);
    };
    visit(sf);
  }
  const status =
    violations.length === 0 ? "PASS" : inv.violation_severity === "WARN" ? "WARN" : "FAIL";
  return {
    ...baseResult(inv, status),
    summary: violations.length ? `${violations.length} sink call(s) flagged` : "no sensitive args in sinks",
    violations: violations.slice(0, 40),
  };
}

function checkMissingPattern(
  repo: string,
  inv: InvariantSpec,
  c: MissingPatternCheck
): InvariantResult {
  const exts = c.extensions?.length ? c.extensions : DEFAULT_EXT;
  const files = listFilesUnderScope(repo, c.scope, exts);
  const scoped = files.filter((fp) => {
    const rel = posix(path.relative(repo, fp));
    return !c.path_substring || rel.includes(c.path_substring);
  });
  if (scoped.length === 0) {
    return {
      ...baseResult(inv, "PASS"),
      summary: "no files matched scope/path filter — skipped",
      violations: [],
    };
  }
  const needles = Array.isArray(c.must_contain) ? c.must_contain : [c.must_contain];
  const missing: Violation[] = [];
  const limit = c.sample_limit ?? 30;
  for (const fp of scoped) {
    const rel = posix(path.relative(repo, fp));
    const text = fs.readFileSync(fp, "utf8");
    const ok = needles.some((n) => text.includes(n));
    if (!ok) {
      missing.push({
        file: rel,
        line: 1,
        col: 1,
        message: `missing token(s): ${needles.join(" | ")}`,
      });
      if (missing.length >= limit) break;
    }
  }
  const status = missing.length === 0 ? "PASS" : "WARN";
  return {
    ...baseResult(inv, status),
    summary:
      missing.length === 0
        ? "all scoped files contain required pattern"
        : `${missing.length} file(s) missing pattern (sample)`,
    violations: missing,
  };
}

function runInvariant(repo: string, inv: InvariantSpec): InvariantResult {
  const raw = inv.check as Record<string, unknown>;
  if (raw.type === "ast_pattern") {
    const q = String(raw.ast_query || "");
    const globs = (Array.isArray(raw.target_files) ? raw.target_files : raw.target_globs) as
      | string[]
      | undefined;
    if (/SwitchStatement/i.test(q) && globs?.length) {
      return checkFailClosedSwitch(repo, inv, { type: "fail_closed_switch", target_globs: globs });
    }
    return {
      ...baseResult(inv, "SKIP"),
      summary: "ast_pattern: only SwitchStatement fail-closed is implemented",
    };
  }
  const ch = inv.check;
  if (ch.type === "fail_closed_switch" && !(ch as FailClosedSwitchCheck).target_globs?.length) {
    const g = raw.target_files;
    if (Array.isArray(g) && g.length) {
      return checkFailClosedSwitch(repo, inv, { type: "fail_closed_switch", target_globs: g as string[] });
    }
  }
  switch (ch.type) {
    case "pattern_count":
      return checkPatternCount(repo, inv, ch);
    case "fail_closed_switch":
      return checkFailClosedSwitch(repo, inv, ch);
    case "sensitive_logger":
      return checkSensitiveLogger(repo, inv, ch);
    case "missing_pattern":
      return checkMissingPattern(repo, inv, ch);
    default:
      return {
        ...baseResult(inv, "SKIP"),
        summary: `unknown check type: ${(ch as { type?: string }).type}`,
      };
  }
}

function printReport(results: InvariantResult[]) {
  console.log(`[OS-INVARIANT] checking ${results.length} invariants...`);
  for (const r of results) {
    const sev = r.status === "FAIL" ? "FAIL" : r.status === "WARN" ? "WARN" : r.status;
    const pad = " ".repeat(Math.max(1, 32 - r.id.length - r.name.length));
    console.log(`  ${r.id} ${r.name}${pad}: ${sev} — ${r.summary}`);
    for (const v of r.violations) {
      console.log(`    ${v.file}:${v.line} — ${v.message}`);
    }
  }
}

function main() {
  const repo = path.resolve(process.argv[2] || process.cwd());
  const invDir = path.resolve(
    process.argv[3] || path.join(repo, ".claude", "invariants")
  );
  const specs = loadSpecs(invDir);
  if (specs.length === 0) {
    console.log("[OS-INVARIANT] checking 0 invariants...");
    console.log(`  skip: no JSON specs in ${posix(path.relative(repo, invDir)) || "."}`);
    writeReport(repo, []);
    return;
  }
  const results = specs.map((s) => runInvariant(repo, s));
  printReport(results);
  writeReport(repo, results);
}

function writeReport(repo: string, results: InvariantResult[]) {
  const out = {
    scanned_at: new Date().toISOString(),
    results: results.map((r) => ({
      id: r.id,
      name: r.name,
      status: r.status,
      summary: r.summary,
      severity: r.severity,
      heuristic_ref: r.heuristic_ref,
      violations: r.violations,
    })),
  };
  const dir = path.join(repo, ".claude");
  try {
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(
      path.join(dir, "invariant-report.json"),
      JSON.stringify(out, null, 2),
      "utf8"
    );
  } catch {
    /* non-fatal */
  }
}

main();
