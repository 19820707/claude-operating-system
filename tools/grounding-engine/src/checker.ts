/**
 * FormalCheck executor — each check type has a proof obligation verified computationally.
 * All checks are time-bounded and error-isolated.
 */

import { execSync, spawnSync } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import { CheckType, CheckResult, FormalCheck } from './types.js';

const DEFAULT_TIMEOUT_MS = 5000;

function elapsed(start: bigint): number {
  return Number(process.hrtime.bigint() - start) / 1_000_000;
}

function runCommand(cmd: string, cwd: string, timeoutMs: number): { stdout: string; stderr: string; error?: string } {
  try {
    const result = spawnSync('cmd', ['/c', cmd], {
      cwd,
      encoding: 'utf8',
      timeout: timeoutMs,
      maxBuffer: 1024 * 1024,
      windowsHide: true,
    });
    if (result.error) {
      // Try bash as fallback (Git Bash / WSL)
      const r2 = spawnSync('bash', ['-c', cmd], {
        cwd,
        encoding: 'utf8',
        timeout: timeoutMs,
        maxBuffer: 1024 * 1024,
        windowsHide: true,
      });
      if (r2.error) return { stdout: '', stderr: '', error: r2.error.message };
      return { stdout: r2.stdout || '', stderr: r2.stderr || '' };
    }
    return { stdout: result.stdout || '', stderr: result.stderr || '' };
  } catch (e) {
    return { stdout: '', stderr: '', error: String(e) };
  }
}

/** Minimal glob-to-regex converter (no external deps). */
function globToRegex(glob: string): RegExp {
  const esc = (s: string) => s.replace(/[.+^${}()|[\]\\]/g, '\\$&');
  let p = glob.replace(/\\/g, '/');
  const parts = p.split('**');
  if (parts.length === 1) {
    const rx = '^' + p.split('*').map(esc).join('[^/]*') + '$';
    return new RegExp(rx, 'i');
  }
  const head = parts[0].replace(/\*/g, '[^/]*');
  const tail = parts.slice(1).join('**').replace(/\*/g, '.*');
  return new RegExp('^' + head + '.*' + tail + '$', 'i');
}

const SKIP_DIRS = new Set(['.git', 'node_modules', 'dist', '.next', 'build', 'vendor', 'coverage']);

function walkFiles(dir: string): string[] {
  const out: string[] = [];
  const visit = (d: string) => {
    let entries: fs.Dirent[] = [];
    try { entries = fs.readdirSync(d, { withFileTypes: true }); } catch { return; }
    for (const e of entries) {
      if (e.isDirectory()) {
        if (SKIP_DIRS.has(e.name)) continue;
        visit(path.join(d, e.name));
      } else if (e.isFile()) {
        out.push(path.join(d, e.name));
      }
    }
  };
  visit(dir);
  return out;
}

// ─── Check: git_state ────────────────────────────────────────────────────────

function checkGitState(check: FormalCheck, repoRoot: string, timeoutMs: number): CheckResult {
  const start = process.hrtime.bigint();
  const cmd = check.command ?? 'git rev-parse --abbrev-ref HEAD';
  const expected = check.expected ?? '';
  const { stdout, error } = runCommand(cmd, repoRoot, timeoutMs);
  if (error) {
    return { type: 'git_state', status: 'ERROR', elapsed_ms: elapsed(start), error };
  }
  const observed = stdout.trim();
  const pass = expected === '' ? true : observed.includes(expected);
  return {
    type: 'git_state',
    status: pass ? 'PASS' : 'FAIL',
    observed: observed.slice(0, 200),
    expected,
    elapsed_ms: elapsed(start),
  };
}

// ─── Check: file_exists ───────────────────────────────────────────────────────

function checkFileExists(check: FormalCheck, repoRoot: string): CheckResult {
  const start = process.hrtime.bigint();
  const target = check.path ?? '';
  if (!target) {
    return { type: 'file_exists', status: 'SKIP', elapsed_ms: elapsed(start), error: 'no path specified' };
  }
  const abs = path.isAbsolute(target) ? target : path.join(repoRoot, target);
  const exists = fs.existsSync(abs);
  return {
    type: 'file_exists',
    status: exists ? 'PASS' : 'FAIL',
    observed: exists ? 'exists' : 'absent',
    expected: 'exists',
    elapsed_ms: elapsed(start),
  };
}

// ─── Check: pattern_absent ────────────────────────────────────────────────────

function checkPatternAbsent(check: FormalCheck, repoRoot: string): CheckResult {
  const start = process.hrtime.bigint();
  const globPat = check.glob ?? check.path ?? '**/*';
  const pattern = check.pattern;
  if (!pattern) {
    return { type: 'pattern_absent', status: 'SKIP', elapsed_ms: elapsed(start), error: 'no pattern specified' };
  }
  let rx: RegExp;
  try { rx = new RegExp(pattern, 'g'); } catch (e) {
    return { type: 'pattern_absent', status: 'ERROR', elapsed_ms: elapsed(start), error: `invalid regex: ${pattern}` };
  }
  const globRx = globToRegex(globPat);
  const allFiles = walkFiles(repoRoot);
  const matching = allFiles.filter(f => {
    const rel = path.relative(repoRoot, f).replace(/\\/g, '/');
    return globRx.test(rel);
  });
  const violations: string[] = [];
  for (const fp of matching) {
    let text = '';
    try { text = fs.readFileSync(fp, 'utf8'); } catch { continue; }
    rx.lastIndex = 0;
    const m = rx.exec(text);
    if (m) {
      violations.push(`${path.relative(repoRoot, fp).replace(/\\/g, '/')}:${text.slice(0, m.index).split('\n').length} — "${m[0].slice(0, 80)}"`);
      if (violations.length >= 5) break;
    }
  }
  if (violations.length === 0) {
    return { type: 'pattern_absent', status: 'PASS', observed: `scanned ${matching.length} files, no match`, expected: 'pattern absent', elapsed_ms: elapsed(start) };
  }
  return {
    type: 'pattern_absent',
    status: 'FAIL',
    observed: violations.join('; '),
    expected: 'pattern absent in all files',
    elapsed_ms: elapsed(start),
  };
}

// ─── Check: invariant_holds ───────────────────────────────────────────────────

function checkInvariantHolds(check: FormalCheck, repoRoot: string): CheckResult {
  const start = process.hrtime.bigint();
  const invId = check.invariant_id;
  if (!invId) {
    return { type: 'invariant_holds', status: 'SKIP', elapsed_ms: elapsed(start), error: 'no invariant_id' };
  }
  const reportPath = path.join(repoRoot, '.claude', 'invariant-report.json');
  if (!fs.existsSync(reportPath)) {
    return { type: 'invariant_holds', status: 'SKIP', elapsed_ms: elapsed(start), error: 'invariant-report.json not found — run invariant engine first' };
  }
  let report: { results?: Array<{ id: string; status: string; summary?: string }> };
  try { report = JSON.parse(fs.readFileSync(reportPath, 'utf8')); } catch {
    return { type: 'invariant_holds', status: 'ERROR', elapsed_ms: elapsed(start), error: 'cannot parse invariant-report.json' };
  }
  const entry = (report.results ?? []).find(r => r.id === invId);
  if (!entry) {
    return { type: 'invariant_holds', status: 'SKIP', elapsed_ms: elapsed(start), error: `${invId} not found in report` };
  }
  const pass = entry.status === 'PASS' || entry.status === 'WARN';
  return {
    type: 'invariant_holds',
    status: pass ? 'PASS' : 'FAIL',
    observed: `${entry.id} ${entry.status}: ${entry.summary ?? ''}`,
    expected: `${invId} PASS or WARN`,
    elapsed_ms: elapsed(start),
  };
}

// ─── Check: external_query ────────────────────────────────────────────────────

function checkExternalQuery(check: FormalCheck, repoRoot: string, timeoutMs: number): CheckResult {
  const start = process.hrtime.bigint();
  const cmd = check.command ?? '';
  const expected = check.expected ?? '';
  if (!cmd) {
    return { type: 'external_query', status: 'SKIP', elapsed_ms: elapsed(start), error: 'no command specified' };
  }
  const { stdout, error } = runCommand(cmd, repoRoot, timeoutMs);
  if (error) {
    return { type: 'external_query', status: 'ERROR', elapsed_ms: elapsed(start), error };
  }
  const observed = stdout.trim();
  const pass = expected === '' ? true : observed.includes(expected);
  return {
    type: 'external_query',
    status: pass ? 'PASS' : 'FAIL',
    observed: observed.slice(0, 300),
    expected,
    elapsed_ms: elapsed(start),
  };
}

// ─── Dispatcher ───────────────────────────────────────────────────────────────

export function executeCheck(check: FormalCheck, repoRoot: string): CheckResult {
  const timeoutMs = check.timeout_ms ?? DEFAULT_TIMEOUT_MS;
  try {
    switch (check.type) {
      case 'git_state':      return checkGitState(check, repoRoot, timeoutMs);
      case 'file_exists':    return checkFileExists(check, repoRoot);
      case 'pattern_absent': return checkPatternAbsent(check, repoRoot);
      case 'invariant_holds': return checkInvariantHolds(check, repoRoot);
      case 'external_query': return checkExternalQuery(check, repoRoot, timeoutMs);
      default: {
        const t: never = check.type;
        return { type: t as CheckType, status: 'SKIP', elapsed_ms: 0, error: `unknown check type: ${t}` };
      }
    }
  } catch (e) {
    return { type: check.type, status: 'ERROR', elapsed_ms: 0, error: String(e) };
  }
}
