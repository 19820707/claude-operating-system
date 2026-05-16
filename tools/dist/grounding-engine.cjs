var __create = Object.create;
var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __getProtoOf = Object.getPrototypeOf;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __copyProps = (to, from, except, desc) => {
  if (from && typeof from === "object" || typeof from === "function") {
    for (let key of __getOwnPropNames(from))
      if (!__hasOwnProp.call(to, key) && key !== except)
        __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
  }
  return to;
};
var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
  // If the importer is in node compatibility mode or this is not an ESM
  // file that has been converted to a CommonJS file using a Babel-
  // compatible transform (i.e. "__esModule" has not been set), then set
  // "default" to the CommonJS "module.exports" for node compatibility.
  isNodeMode || !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: true }) : target,
  mod
));

// tools/grounding-engine/src/index.ts
var fs4 = __toESM(require("fs"));
var path4 = __toESM(require("path"));

// tools/grounding-engine/src/types.ts
var GROUNDING_THRESHOLD = 0.6;
var STALE_THRESHOLD = 0.8;
var STATE_FILE = ".claude/grounding-state.json";
var REPORT_FILE = ".claude/grounding-report.json";

// tools/grounding-engine/src/state.ts
var fs = __toESM(require("fs"));
var path = __toESM(require("path"));
var os = __toESM(require("os"));
var crypto = __toESM(require("crypto"));
var SCHEMA_VERSION = "1";
function loadState(repoRoot) {
  const fp = path.join(repoRoot, STATE_FILE);
  if (!fs.existsSync(fp)) {
    return emptyState();
  }
  try {
    const raw = fs.readFileSync(fp, "utf8");
    const parsed = JSON.parse(raw);
    return {
      version: SCHEMA_VERSION,
      assertions: Array.isArray(parsed.assertions) ? parsed.assertions : [],
      contradictions: Array.isArray(parsed.contradictions) ? parsed.contradictions : [],
      metrics: parsed.metrics,
      last_full_verify: parsed.last_full_verify,
      auto_generated_at: parsed.auto_generated_at
    };
  } catch {
    return emptyState();
  }
}
function saveState(state, repoRoot) {
  const fp = path.join(repoRoot, STATE_FILE);
  const dir = path.dirname(fp);
  fs.mkdirSync(dir, { recursive: true });
  const content = JSON.stringify(state, null, 2).replace(/\r\n/g, "\n").replace(/\r/g, "\n");
  const tmp = path.join(os.tmpdir(), `grounding-${crypto.randomBytes(6).toString("hex")}.json`);
  fs.writeFileSync(tmp, content, { encoding: "utf8" });
  try {
    fs.renameSync(tmp, fp);
  } catch {
    fs.copyFileSync(tmp, fp);
    try {
      fs.unlinkSync(tmp);
    } catch {
    }
  }
}
function emptyState() {
  return { version: SCHEMA_VERSION, assertions: [], contradictions: [] };
}
function nextAssertionId(existing) {
  const current = new Set(existing.assertions.map((a) => a.id));
  let n = existing.assertions.length + 1;
  while (current.has(`GRND-${String(n).padStart(3, "0")}`)) n++;
  return `GRND-${String(n).padStart(3, "0")}`;
}
function nextContradictionId(existing) {
  const current = new Set(existing.contradictions.map((c) => c.id));
  let n = existing.contradictions.length + 1;
  while (current.has(`CONTR-${String(n).padStart(3, "0")}`)) n++;
  return `CONTR-${String(n).padStart(3, "0")}`;
}

// tools/grounding-engine/src/checker.ts
var import_child_process = require("child_process");
var fs2 = __toESM(require("fs"));
var path2 = __toESM(require("path"));
var DEFAULT_TIMEOUT_MS = 5e3;
function elapsed(start) {
  return Number(process.hrtime.bigint() - start) / 1e6;
}
function runCommand(cmd, cwd, timeoutMs) {
  try {
    const result = (0, import_child_process.spawnSync)("cmd", ["/c", cmd], {
      cwd,
      encoding: "utf8",
      timeout: timeoutMs,
      maxBuffer: 1024 * 1024,
      windowsHide: true
    });
    if (result.error) {
      const r2 = (0, import_child_process.spawnSync)("bash", ["-c", cmd], {
        cwd,
        encoding: "utf8",
        timeout: timeoutMs,
        maxBuffer: 1024 * 1024,
        windowsHide: true
      });
      if (r2.error) return { stdout: "", stderr: "", error: r2.error.message };
      return { stdout: r2.stdout || "", stderr: r2.stderr || "" };
    }
    return { stdout: result.stdout || "", stderr: result.stderr || "" };
  } catch (e) {
    return { stdout: "", stderr: "", error: String(e) };
  }
}
function globToRegex(glob) {
  const esc = (s) => s.replace(/[.+^${}()|[\]\\]/g, "\\$&");
  let p = glob.replace(/\\/g, "/");
  const parts = p.split("**");
  if (parts.length === 1) {
    const rx = "^" + p.split("*").map(esc).join("[^/]*") + "$";
    return new RegExp(rx, "i");
  }
  const head = parts[0].replace(/\*/g, "[^/]*");
  const tail = parts.slice(1).join("**").replace(/\*/g, ".*");
  return new RegExp("^" + head + ".*" + tail + "$", "i");
}
var SKIP_DIRS = /* @__PURE__ */ new Set([".git", "node_modules", "dist", ".next", "build", "vendor", "coverage"]);
function walkFiles(dir) {
  const out = [];
  const visit = (d) => {
    let entries = [];
    try {
      entries = fs2.readdirSync(d, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      if (e.isDirectory()) {
        if (SKIP_DIRS.has(e.name)) continue;
        visit(path2.join(d, e.name));
      } else if (e.isFile()) {
        out.push(path2.join(d, e.name));
      }
    }
  };
  visit(dir);
  return out;
}
function checkGitState(check, repoRoot, timeoutMs) {
  const start = process.hrtime.bigint();
  const cmd = check.command ?? "git rev-parse --abbrev-ref HEAD";
  const expected = check.expected ?? "";
  const { stdout, error } = runCommand(cmd, repoRoot, timeoutMs);
  if (error) {
    return { type: "git_state", status: "ERROR", elapsed_ms: elapsed(start), error };
  }
  const observed = stdout.trim();
  const pass = expected === "" ? true : observed.includes(expected);
  return {
    type: "git_state",
    status: pass ? "PASS" : "FAIL",
    observed: observed.slice(0, 200),
    expected,
    elapsed_ms: elapsed(start)
  };
}
function checkFileExists(check, repoRoot) {
  const start = process.hrtime.bigint();
  const target = check.path ?? "";
  if (!target) {
    return { type: "file_exists", status: "SKIP", elapsed_ms: elapsed(start), error: "no path specified" };
  }
  const abs = path2.isAbsolute(target) ? target : path2.join(repoRoot, target);
  const exists = fs2.existsSync(abs);
  return {
    type: "file_exists",
    status: exists ? "PASS" : "FAIL",
    observed: exists ? "exists" : "absent",
    expected: "exists",
    elapsed_ms: elapsed(start)
  };
}
function checkPatternAbsent(check, repoRoot) {
  const start = process.hrtime.bigint();
  const globPat = check.glob ?? check.path ?? "**/*";
  const pattern = check.pattern;
  if (!pattern) {
    return { type: "pattern_absent", status: "SKIP", elapsed_ms: elapsed(start), error: "no pattern specified" };
  }
  let rx;
  try {
    rx = new RegExp(pattern, "g");
  } catch (e) {
    return { type: "pattern_absent", status: "ERROR", elapsed_ms: elapsed(start), error: `invalid regex: ${pattern}` };
  }
  const globRx = globToRegex(globPat);
  const allFiles = walkFiles(repoRoot);
  const matching = allFiles.filter((f) => {
    const rel = path2.relative(repoRoot, f).replace(/\\/g, "/");
    return globRx.test(rel);
  });
  const violations = [];
  for (const fp of matching) {
    let text = "";
    try {
      text = fs2.readFileSync(fp, "utf8");
    } catch {
      continue;
    }
    rx.lastIndex = 0;
    const m = rx.exec(text);
    if (m) {
      violations.push(`${path2.relative(repoRoot, fp).replace(/\\/g, "/")}:${text.slice(0, m.index).split("\n").length} \u2014 "${m[0].slice(0, 80)}"`);
      if (violations.length >= 5) break;
    }
  }
  if (violations.length === 0) {
    return { type: "pattern_absent", status: "PASS", observed: `scanned ${matching.length} files, no match`, expected: "pattern absent", elapsed_ms: elapsed(start) };
  }
  return {
    type: "pattern_absent",
    status: "FAIL",
    observed: violations.join("; "),
    expected: "pattern absent in all files",
    elapsed_ms: elapsed(start)
  };
}
function checkInvariantHolds(check, repoRoot) {
  const start = process.hrtime.bigint();
  const invId = check.invariant_id;
  if (!invId) {
    return { type: "invariant_holds", status: "SKIP", elapsed_ms: elapsed(start), error: "no invariant_id" };
  }
  const reportPath = path2.join(repoRoot, ".claude", "invariant-report.json");
  if (!fs2.existsSync(reportPath)) {
    return { type: "invariant_holds", status: "SKIP", elapsed_ms: elapsed(start), error: "invariant-report.json not found \u2014 run invariant engine first" };
  }
  let report;
  try {
    report = JSON.parse(fs2.readFileSync(reportPath, "utf8"));
  } catch {
    return { type: "invariant_holds", status: "ERROR", elapsed_ms: elapsed(start), error: "cannot parse invariant-report.json" };
  }
  const entry = (report.results ?? []).find((r) => r.id === invId);
  if (!entry) {
    return { type: "invariant_holds", status: "SKIP", elapsed_ms: elapsed(start), error: `${invId} not found in report` };
  }
  const pass = entry.status === "PASS" || entry.status === "WARN";
  return {
    type: "invariant_holds",
    status: pass ? "PASS" : "FAIL",
    observed: `${entry.id} ${entry.status}: ${entry.summary ?? ""}`,
    expected: `${invId} PASS or WARN`,
    elapsed_ms: elapsed(start)
  };
}
function checkExternalQuery(check, repoRoot, timeoutMs) {
  const start = process.hrtime.bigint();
  const cmd = check.command ?? "";
  const expected = check.expected ?? "";
  if (!cmd) {
    return { type: "external_query", status: "SKIP", elapsed_ms: elapsed(start), error: "no command specified" };
  }
  const { stdout, error } = runCommand(cmd, repoRoot, timeoutMs);
  if (error) {
    return { type: "external_query", status: "ERROR", elapsed_ms: elapsed(start), error };
  }
  const observed = stdout.trim();
  const pass = expected === "" ? true : observed.includes(expected);
  return {
    type: "external_query",
    status: pass ? "PASS" : "FAIL",
    observed: observed.slice(0, 300),
    expected,
    elapsed_ms: elapsed(start)
  };
}
function executeCheck(check, repoRoot) {
  const timeoutMs = check.timeout_ms ?? DEFAULT_TIMEOUT_MS;
  try {
    switch (check.type) {
      case "git_state":
        return checkGitState(check, repoRoot, timeoutMs);
      case "file_exists":
        return checkFileExists(check, repoRoot);
      case "pattern_absent":
        return checkPatternAbsent(check, repoRoot);
      case "invariant_holds":
        return checkInvariantHolds(check, repoRoot);
      case "external_query":
        return checkExternalQuery(check, repoRoot, timeoutMs);
      default: {
        const t = check.type;
        return { type: t, status: "SKIP", elapsed_ms: 0, error: `unknown check type: ${t}` };
      }
    }
  } catch (e) {
    return { type: check.type, status: "ERROR", elapsed_ms: 0, error: String(e) };
  }
}

// tools/grounding-engine/src/metrics.ts
var LN2 = Math.LN2;
function decayFraction(lastVerifiedAt, halfLifeHours) {
  if (!lastVerifiedAt) return 1;
  const elapsedMs = Date.now() - new Date(lastVerifiedAt).getTime();
  if (elapsedMs <= 0) return 0;
  const elapsedHours = elapsedMs / (1e3 * 3600);
  const lambda = LN2 / Math.max(0.1, halfLifeHours);
  return 1 - Math.exp(-lambda * elapsedHours);
}
function effectiveConfidence(a) {
  const decay = decayFraction(a.last_verified_at, a.decay_half_life_hours);
  return a.base_confidence * (1 - decay);
}
function refreshStatus(a) {
  const eff = effectiveConfidence(a);
  const decayFrac = decayFraction(a.last_verified_at, a.decay_half_life_hours);
  if (a.contradiction_ids && a.contradiction_ids.length > 0) {
    a.status = "CONTRADICTION";
  } else if (!a.last_check || a.last_check.status === "SKIP") {
    a.status = "UNVERIFIED";
  } else if (a.last_check.status !== "PASS") {
    a.status = "FAILED";
  } else if (decayFrac >= STALE_THRESHOLD) {
    a.status = "STALE";
  } else {
    a.status = "GROUNDED";
  }
  a.confidence = Math.max(0, eff);
  return a;
}
function computeMetrics(state) {
  const assertions = state.assertions.map((a) => refreshStatus({ ...a }));
  const total = assertions.length;
  if (total === 0) {
    const empty = {
      total_assertions: 0,
      verified_count: 0,
      coverage: 0,
      accuracy: 0,
      staleness: 1,
      composite_score: 0,
      gap_declared: true,
      contradiction_count: 0,
      computed_at: (/* @__PURE__ */ new Date()).toISOString()
    };
    return empty;
  }
  const verified = assertions.filter((a) => a.last_check && a.last_check.status !== "SKIP");
  const passed = verified.filter((a) => a.last_check.status === "PASS");
  const coverage = total > 0 ? verified.length / total : 0;
  const accuracy = verified.length > 0 ? passed.length / verified.length : 0;
  const meanStaleness = total > 0 ? assertions.reduce((sum, a) => sum + decayFraction(a.last_verified_at, a.decay_half_life_hours), 0) / total : 1;
  const composite = coverage * accuracy * (1 - meanStaleness);
  const contradictions = assertions.filter((a) => a.status === "CONTRADICTION").length;
  return {
    total_assertions: total,
    verified_count: verified.length,
    coverage: round4(coverage),
    accuracy: round4(accuracy),
    staleness: round4(meanStaleness),
    composite_score: round4(composite),
    gap_declared: composite < GROUNDING_THRESHOLD,
    contradiction_count: contradictions,
    computed_at: (/* @__PURE__ */ new Date()).toISOString()
  };
}
function round4(n) {
  return Math.round(n * 1e4) / 1e4;
}
function scoreGrade(score) {
  if (score >= 0.85) return "A \u2014 highly grounded";
  if (score >= 0.7) return "B \u2014 well grounded";
  if (score >= 0.6) return "C \u2014 adequately grounded";
  if (score >= 0.45) return "D \u2014 grounding gap present";
  return "F \u2014 critical grounding gap";
}

// tools/grounding-engine/src/auto-generate.ts
var fs3 = __toESM(require("fs"));
var path3 = __toESM(require("path"));
var NOW = (/* @__PURE__ */ new Date()).toISOString();
var CLAUDE_DIR = ".claude";
var TEMPLATE_INVARIANTS = "templates/invariants/core.json";
function fromWorldModel(repoRoot, state) {
  const fp = path3.join(repoRoot, CLAUDE_DIR, "world-model.json");
  if (!fs3.existsSync(fp)) return [];
  let wm;
  try {
    wm = JSON.parse(fs3.readFileSync(fp, "utf8"));
  } catch {
    return [];
  }
  const results = [];
  const existingPaths = new Set(
    state.assertions.filter((a) => a.formal_check.type === "file_exists" && a.source === "auto-world-model").map((a) => a.formal_check.path ?? "")
  );
  for (const entity of wm.entities ?? []) {
    if (entity.type !== "file") continue;
    if (!entity.path) continue;
    if ((entity.risk ?? 0) < 0.3) continue;
    if (existingPaths.has(entity.path)) continue;
    const id = nextAssertionId({ ...state, assertions: [...state.assertions, ...results] });
    results.push({
      id,
      claim: `High-risk file exists: ${entity.path}`,
      formal_check: { type: "file_exists", path: entity.path },
      confidence: entity.confidence ?? 0.8,
      base_confidence: entity.confidence ?? 0.8,
      decay_half_life_hours: 48,
      status: "UNVERIFIED",
      source: "auto-world-model",
      tags: ["world-model", "file", `risk:${((entity.risk ?? 0) * 100).toFixed(0)}`],
      created_at: NOW
    });
  }
  const branch = wm.global_state?.branch;
  if (branch && !state.assertions.some((a) => a.source === "auto-world-model" && a.formal_check.type === "git_state" && a.claim.includes("branch"))) {
    const id = nextAssertionId({ ...state, assertions: [...state.assertions, ...results] });
    results.push({
      id,
      claim: `Repository is on branch: ${branch}`,
      formal_check: { type: "git_state", command: "git rev-parse --abbrev-ref HEAD", expected: branch },
      confidence: 0.9,
      base_confidence: 0.9,
      decay_half_life_hours: 6,
      status: "UNVERIFIED",
      source: "auto-world-model",
      tags: ["world-model", "git", "branch"],
      created_at: NOW
    });
  }
  return results;
}
function fromEpistemicState(repoRoot, state) {
  const fp = path3.join(repoRoot, CLAUDE_DIR, "epistemic-state.json");
  if (!fs3.existsSync(fp)) return [];
  let es;
  try {
    es = JSON.parse(fs3.readFileSync(fp, "utf8"));
  } catch {
    return [];
  }
  const results = [];
  const existingKeys = new Set(
    state.assertions.filter((a) => a.source === "auto-epistemic").map((a) => a.tags?.find((t) => t.startsWith("fact:"))?.slice(5) ?? "")
  );
  for (const [key, fact] of Object.entries(es.facts ?? {})) {
    if (existingKeys.has(key)) continue;
    if (fact.status !== "KNOWN" || fact.confidence < 0.6) continue;
    const formalCheck = buildEpistemicCheck(key, fact);
    if (!formalCheck) continue;
    const id = nextAssertionId({ ...state, assertions: [...state.assertions, ...results] });
    results.push({
      id,
      claim: `Epistemic fact confirmed: ${key} = ${String(fact.value).slice(0, 100)}`,
      formal_check: formalCheck,
      confidence: fact.confidence,
      base_confidence: fact.confidence,
      decay_half_life_hours: 24,
      status: "UNVERIFIED",
      source: "auto-epistemic",
      tags: ["epistemic", `fact:${key}`, ...fact.tags ?? []],
      created_at: NOW
    });
  }
  return results;
}
function buildEpistemicCheck(key, fact) {
  if (key.startsWith("exit_code:")) {
    const filePart = key.slice("exit_code:".length);
    const filePath = filePart.replace(/\./g, "/").replace(/\/ps1$/, ".ps1");
    return { type: "file_exists", path: filePath };
  }
  if (key === "repo.branch" && fact.value) {
    return { type: "git_state", command: "git rev-parse --abbrev-ref HEAD", expected: String(fact.value) };
  }
  return null;
}
function fromInvariants(repoRoot, state) {
  const fp = path3.join(repoRoot, TEMPLATE_INVARIANTS);
  if (!fs3.existsSync(fp)) return [];
  let raw;
  try {
    raw = JSON.parse(fs3.readFileSync(fp, "utf8"));
  } catch {
    return [];
  }
  const specs = [];
  if (Array.isArray(raw)) {
    specs.push(...raw);
  } else if (raw && typeof raw === "object" && Array.isArray(raw.invariants)) {
    specs.push(...raw.invariants);
  }
  const results = [];
  const existingInvIds = new Set(
    state.assertions.filter((a) => a.source === "auto-invariant").map((a) => a.formal_check.invariant_id ?? "")
  );
  for (const spec of specs) {
    if (!spec.id) continue;
    if (spec.status === "DEPRECATED" || spec.status === "INACTIVE") continue;
    if (existingInvIds.has(spec.id)) continue;
    const severity = spec.violation_severity ?? "WARN";
    const baseConf = severity === "CRITICAL" ? 0.95 : severity === "HIGH" ? 0.85 : 0.75;
    const id = nextAssertionId({ ...state, assertions: [...state.assertions, ...results] });
    results.push({
      id,
      claim: `Invariant ${spec.id} holds: ${spec.name}`,
      formal_check: { type: "invariant_holds", invariant_id: spec.id },
      confidence: baseConf,
      base_confidence: baseConf,
      decay_half_life_hours: 72,
      status: "UNVERIFIED",
      source: "auto-invariant",
      tags: ["invariant", spec.id, `severity:${severity}`],
      created_at: NOW
    });
  }
  return results;
}
function fromSessionState(repoRoot, state) {
  const fp = path3.join(repoRoot, CLAUDE_DIR, "session-state.md");
  if (!fs3.existsSync(fp)) return [];
  let text = "";
  try {
    text = fs3.readFileSync(fp, "utf8");
  } catch {
    return [];
  }
  const results = [];
  const hasSessionAssertion = state.assertions.some(
    (a) => a.source === "auto-session" && a.formal_check.type === "file_exists" && a.formal_check.path === `${CLAUDE_DIR}/session-state.md`
  );
  if (!hasSessionAssertion) {
    const id = nextAssertionId({ ...state, assertions: [...state.assertions, ...results] });
    results.push({
      id,
      claim: "Session state file exists and is maintained",
      formal_check: { type: "file_exists", path: `${CLAUDE_DIR}/session-state.md` },
      confidence: 1,
      base_confidence: 1,
      decay_half_life_hours: 12,
      status: "UNVERIFIED",
      source: "auto-session",
      tags: ["session", "continuity"],
      created_at: NOW
    });
  }
  const hasLearningAssertion = state.assertions.some(
    (a) => a.source === "auto-session" && a.formal_check.path === `${CLAUDE_DIR}/learning-log.md`
  );
  if (!hasLearningAssertion) {
    const id = nextAssertionId({ ...state, assertions: [...state.assertions, ...results] });
    results.push({
      id,
      claim: "Learning log exists (phase continuity)",
      formal_check: { type: "file_exists", path: `${CLAUDE_DIR}/learning-log.md` },
      confidence: 0.9,
      base_confidence: 0.9,
      decay_half_life_hours: 24,
      status: "UNVERIFIED",
      source: "auto-session",
      tags: ["session", "learning-log"],
      created_at: NOW
    });
  }
  const hasH16Assertion = state.assertions.some(
    (a) => a.source === "auto-session" && a.tags?.includes("H16")
  );
  if (!hasH16Assertion) {
    const id = nextAssertionId({ ...state, assertions: [...state.assertions, ...results] });
    results.push({
      id,
      claim: "No unbraced PS variable followed by colon in tools/ (H16 invariant)",
      formal_check: {
        type: "pattern_absent",
        glob: "tools/**/*.ps1",
        pattern: '"[^"]*\\$[A-Za-z][A-Za-z0-9_]*:[^:]'
      },
      confidence: 0.95,
      base_confidence: 0.95,
      decay_half_life_hours: 120,
      status: "UNVERIFIED",
      source: "auto-session",
      tags: ["session", "H16", "powershell", "invariant"],
      created_at: NOW
    });
  }
  return results;
}
function autoGenerate(state, repoRoot) {
  const added = [];
  const wm = fromWorldModel(repoRoot, state);
  added.push(...wm);
  const s1 = { ...state, assertions: [...state.assertions, ...added] };
  const ep = fromEpistemicState(repoRoot, s1);
  added.push(...ep);
  const s2 = { ...state, assertions: [...state.assertions, ...added] };
  const inv = fromInvariants(repoRoot, s2);
  added.push(...inv);
  const s3 = { ...state, assertions: [...state.assertions, ...added] };
  const sess = fromSessionState(repoRoot, s3);
  added.push(...sess);
  const finalState = {
    ...state,
    assertions: [...state.assertions, ...added],
    auto_generated_at: NOW
  };
  return { added, state: finalState };
}

// tools/grounding-engine/src/index.ts
var REPO_ROOT = process.argv[2] ? path4.resolve(process.argv[2]) : process.cwd();
var MODE = process.argv[3] ?? "report";
var EXTRA_ARGS = process.argv.slice(4);
function parseArgs(args) {
  const out = {};
  for (let i = 0; i < args.length; i++) {
    if (args[i].startsWith("--") && args[i + 1] !== void 0 && !args[i + 1].startsWith("--")) {
      out[args[i].slice(2)] = args[i + 1];
      i++;
    } else if (args[i].startsWith("--")) {
      out[args[i].slice(2)] = "true";
    }
  }
  return out;
}
function modeVerify(state) {
  const now = (/* @__PURE__ */ new Date()).toISOString();
  console.log(`[GROUNDING] verify \u2014 ${state.assertions.length} assertions`);
  const updated = [];
  for (const assertion of state.assertions) {
    process.stdout.write(`  [${assertion.id}] ${assertion.claim.slice(0, 60)}...`);
    const result = executeCheck(assertion.formal_check, REPO_ROOT);
    const pass = result.status === "PASS";
    const confidence = pass ? assertion.base_confidence : Math.max(0, assertion.confidence * 0.5);
    const refreshed = {
      ...assertion,
      last_check: result,
      last_verified_at: now,
      confidence
    };
    const final = refreshStatus(refreshed);
    updated.push(final);
    console.log(` ${result.status} (${result.elapsed_ms.toFixed(0)}ms)`);
    if (result.status !== "PASS" && result.observed) {
      console.log(`    observed: ${result.observed.slice(0, 120)}`);
    }
    if (result.error) {
      console.log(`    error: ${result.error.slice(0, 120)}`);
    }
  }
  const contradictions = detectContradictions(updated, state.contradictions);
  for (const c of contradictions) {
    const a = updated.find((x) => x.id === c.assertion_a);
    const b = updated.find((x) => x.id === c.assertion_b);
    if (a) {
      a.contradiction_ids = [...a.contradiction_ids ?? [], c.id];
      a.status = "CONTRADICTION";
    }
    if (b) {
      b.contradiction_ids = [...b.contradiction_ids ?? [], c.id];
      b.status = "CONTRADICTION";
    }
  }
  return { ...state, assertions: updated, contradictions, last_full_verify: now };
}
function detectContradictions(assertions, existing) {
  const all = [...existing];
  const existingPairs = new Set(existing.map((c) => `${c.assertion_a}:${c.assertion_b}`));
  const now = (/* @__PURE__ */ new Date()).toISOString();
  const fileExists = assertions.filter((a) => a.formal_check.type === "file_exists" && a.last_check);
  for (let i = 0; i < fileExists.length; i++) {
    for (let j = i + 1; j < fileExists.length; j++) {
      const a = fileExists[i];
      const b = fileExists[j];
      if (a.formal_check.path !== b.formal_check.path) continue;
      const aPass = a.last_check?.status === "PASS";
      const bPass = b.last_check?.status === "PASS";
      if (aPass === bPass) continue;
      const pairKey = `${a.id}:${b.id}`;
      if (existingPairs.has(pairKey)) continue;
      const fakeState = { version: "1", assertions, contradictions: all };
      const cId = nextContradictionId(fakeState);
      all.push({
        id: cId,
        assertion_a: a.id,
        assertion_b: b.id,
        strategy: "newer_wins",
        detected_at: now
      });
      existingPairs.add(pairKey);
    }
  }
  const gitState = assertions.filter((a) => a.formal_check.type === "git_state" && a.last_check);
  for (let i = 0; i < gitState.length; i++) {
    for (let j = i + 1; j < gitState.length; j++) {
      const a = gitState[i];
      const b = gitState[j];
      if (a.formal_check.command !== b.formal_check.command) continue;
      if (a.last_check?.observed !== b.last_check?.observed) continue;
      const aPass = a.last_check?.status === "PASS";
      const bPass = b.last_check?.status === "PASS";
      if (aPass === bPass) continue;
      const pairKey = `${a.id}:${b.id}`;
      if (existingPairs.has(pairKey)) continue;
      const fakeState = { version: "1", assertions, contradictions: all };
      const cId = nextContradictionId(fakeState);
      all.push({
        id: cId,
        assertion_a: a.id,
        assertion_b: b.id,
        strategy: "higher_confidence_wins",
        detected_at: now
      });
      existingPairs.add(pairKey);
    }
  }
  return all;
}
function modeAutoGenerate(state) {
  const { added, state: newState } = autoGenerate(state, REPO_ROOT);
  console.log(`[GROUNDING] auto-generate \u2014 added ${added.length} assertion(s)`);
  for (const a of added) {
    console.log(`  ${a.id}: [${a.source}] ${a.claim.slice(0, 80)}`);
  }
  return newState;
}
function modeAssert(state, args) {
  const existingId = args.id;
  const claim = args.claim;
  const type = args.type;
  if (!claim || !type) {
    console.error("[GROUNDING] assert: --claim and --type are required");
    process.exit(1);
  }
  const id = existingId ?? nextAssertionId(state);
  const existing = state.assertions.find((a) => a.id === id);
  const baseConf = parseFloat(args.confidence ?? "0.8");
  const formalCheck = { type };
  if (args.command) formalCheck.command = args.command;
  if (args.expected) formalCheck.expected = args.expected;
  if (args.path) formalCheck.path = args.path;
  if (args.glob) formalCheck.glob = args.glob;
  if (args.pattern) formalCheck.pattern = args.pattern;
  if (args["invariant-id"]) formalCheck.invariant_id = args["invariant-id"];
  if (args.timeout) formalCheck.timeout_ms = parseInt(args.timeout, 10);
  const newAssertion = {
    ...existing ?? {},
    id,
    claim,
    formal_check: formalCheck,
    confidence: baseConf,
    base_confidence: baseConf,
    decay_half_life_hours: parseFloat(args["decay-hours"] ?? "48"),
    status: "UNVERIFIED",
    source: "manual",
    tags: args.tags ? args.tags.split(",") : existing?.tags ?? [],
    created_at: existing?.created_at ?? (/* @__PURE__ */ new Date()).toISOString()
  };
  const assertions = existing ? state.assertions.map((a) => a.id === id ? newAssertion : a) : [...state.assertions, newAssertion];
  console.log(`[GROUNDING] assert \u2014 ${existing ? "updated" : "added"} ${id}: ${claim.slice(0, 80)}`);
  return { ...state, assertions };
}
function modeContradictionResolve(state) {
  const now = (/* @__PURE__ */ new Date()).toISOString();
  const updatedContradictions = [];
  const resolvedAssertionIds = /* @__PURE__ */ new Set();
  for (const c of state.contradictions) {
    if (c.resolved_at) {
      updatedContradictions.push(c);
      continue;
    }
    const a = state.assertions.find((x) => x.id === c.assertion_a);
    const b = state.assertions.find((x) => x.id === c.assertion_b);
    if (!a || !b) {
      updatedContradictions.push(c);
      continue;
    }
    let winner;
    let reason;
    switch (c.strategy) {
      case "newer_wins": {
        const ta = a.last_verified_at ? new Date(a.last_verified_at).getTime() : 0;
        const tb = b.last_verified_at ? new Date(b.last_verified_at).getTime() : 0;
        winner = ta >= tb ? a.id : b.id;
        reason = `newer_wins: ${winner} verified at ${winner === a.id ? a.last_verified_at : b.last_verified_at}`;
        break;
      }
      case "higher_confidence_wins": {
        winner = a.confidence >= b.confidence ? a.id : b.id;
        reason = `higher_confidence_wins: ${winner} conf=${winner === a.id ? a.confidence : b.confidence}`;
        break;
      }
      case "require_human":
        winner = void 0;
        reason = "requires human resolution";
        break;
    }
    console.log(`[GROUNDING] contradiction ${c.id}: ${a.id} vs ${b.id} \u2014 ${reason ?? "pending"}`);
    updatedContradictions.push({ ...c, resolved_at: winner ? now : void 0, winner, reason });
    if (winner) resolvedAssertionIds.add(winner === a.id ? b.id : a.id);
  }
  const updatedAssertions = state.assertions.map((a) => {
    if (!resolvedAssertionIds.has(a.id)) return a;
    const cleared = { ...a, contradiction_ids: [] };
    return refreshStatus(cleared);
  });
  return { ...state, assertions: updatedAssertions, contradictions: updatedContradictions };
}
function modeReport(state) {
  const metrics = computeMetrics(state);
  const grade = scoreGrade(metrics.composite_score);
  console.log("[GROUNDING] Grounding Verification Report");
  console.log("\u2500".repeat(60));
  console.log(`  Composite Score : ${(metrics.composite_score * 100).toFixed(1)}%  (${grade})`);
  console.log(`  Coverage        : ${(metrics.coverage * 100).toFixed(1)}%  (${metrics.verified_count}/${metrics.total_assertions} assertions verified)`);
  console.log(`  Accuracy        : ${(metrics.accuracy * 100).toFixed(1)}%  (checks passing)`);
  console.log(`  Staleness       : ${(metrics.staleness * 100).toFixed(1)}%  (mean decay)`);
  if (metrics.contradiction_count > 0) {
    console.log(`  Contradictions  : ${metrics.contradiction_count} (resolve with contradiction-resolve mode)`);
  }
  if (metrics.gap_declared) {
    console.log(`  STATUS          : GROUNDING GAP \u2014 score ${(metrics.composite_score * 100).toFixed(1)}% < ${(GROUNDING_THRESHOLD * 100).toFixed(0)}% threshold`);
  } else {
    console.log(`  STATUS          : GROUNDED`);
  }
  console.log("\u2500".repeat(60));
  if (state.assertions.length > 0) {
    console.log("  Assertions:");
    for (const a of state.assertions.map((x) => refreshStatus({ ...x }))) {
      const decay = decayFraction(a.last_verified_at, a.decay_half_life_hours);
      const icon = a.status === "GROUNDED" ? "\u2713" : a.status === "FAILED" ? "\u2717" : a.status === "CONTRADICTION" ? "!" : a.status === "STALE" ? "~" : "?";
      const conf = `${(a.confidence * 100).toFixed(0)}%`;
      const stale = `decay=${(decay * 100).toFixed(0)}%`;
      console.log(`    ${icon} ${a.id}  ${a.claim.slice(0, 55).padEnd(55)}  [${a.status.padEnd(13)}] conf=${conf} ${stale}`);
    }
  }
}
function modeScore(state) {
  const metrics = computeMetrics(state);
  console.log(metrics.composite_score.toFixed(4));
}
function writeReport(state) {
  const metrics = computeMetrics(state);
  const out = {
    generated_at: (/* @__PURE__ */ new Date()).toISOString(),
    metrics,
    assertions: state.assertions.map((a) => {
      const r = refreshStatus({ ...a });
      return {
        id: r.id,
        claim: r.claim,
        status: r.status,
        confidence: r.confidence,
        last_verified_at: r.last_verified_at,
        last_check: r.last_check,
        source: r.source,
        tags: r.tags
      };
    }),
    contradictions: state.contradictions
  };
  const fp = path4.join(REPO_ROOT, REPORT_FILE);
  try {
    fs4.mkdirSync(path4.dirname(fp), { recursive: true });
    fs4.writeFileSync(fp, JSON.stringify(out, null, 2).replace(/\r\n/g, "\n"), "utf8");
  } catch {
  }
}
function main() {
  let state = loadState(REPO_ROOT);
  const args = parseArgs(EXTRA_ARGS);
  switch (MODE) {
    case "verify": {
      state = modeVerify(state);
      saveState(state, REPO_ROOT);
      writeReport(state);
      const metrics = computeMetrics(state);
      console.log(`
[GROUNDING] score=${(metrics.composite_score * 100).toFixed(1)}% gap=${metrics.gap_declared}`);
      if (metrics.gap_declared) {
        console.log(`[GROUNDING] WARN: grounding gap \u2014 score ${(metrics.composite_score * 100).toFixed(1)}% < ${(GROUNDING_THRESHOLD * 100).toFixed(0)}%`);
      }
      break;
    }
    case "auto-generate": {
      state = modeAutoGenerate(state);
      saveState(state, REPO_ROOT);
      const metrics = computeMetrics(state);
      console.log(`[GROUNDING] state: ${state.assertions.length} total assertions, score=${(metrics.composite_score * 100).toFixed(1)}%`);
      break;
    }
    case "assert": {
      state = modeAssert(state, args);
      saveState(state, REPO_ROOT);
      break;
    }
    case "report": {
      modeReport(state);
      writeReport(state);
      break;
    }
    case "score": {
      modeScore(state);
      break;
    }
    case "contradiction-resolve": {
      state = modeContradictionResolve(state);
      saveState(state, REPO_ROOT);
      modeReport(state);
      writeReport(state);
      break;
    }
    default:
      console.error(`[GROUNDING] unknown mode: ${MODE}`);
      console.error("  modes: verify | auto-generate | assert | report | score | contradiction-resolve");
      process.exit(1);
  }
}
main();
