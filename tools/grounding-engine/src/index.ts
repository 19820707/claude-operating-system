/**
 * Grounding Verification Engine — CLI entry point.
 * Usage: node grounding-engine.cjs <mode> [options]
 *
 * Modes:
 *   verify          Run all formal checks; update state; detect contradictions
 *   auto-generate   Auto-generate assertions from OS artifacts
 *   assert          Add or update a single assertion (CLI args)
 *   report          Print grounding report (reads state; does not re-verify)
 *   score           Print composite score only (for scripting)
 *   contradiction-resolve  Apply resolution strategies to pending contradictions
 */

import * as fs from 'fs';
import * as path from 'path';
import { GroundingAssertion, GroundingState, ContradictionSet, GROUNDING_THRESHOLD, REPORT_FILE } from './types.js';
import { loadState, saveState, nextAssertionId, nextContradictionId } from './state.js';
import { executeCheck } from './checker.js';
import { computeMetrics, refreshStatus, scoreGrade, decayFraction } from './metrics.js';
import { autoGenerate } from './auto-generate.js';

const REPO_ROOT = process.argv[2] ? path.resolve(process.argv[2]) : process.cwd();
const MODE = process.argv[3] ?? 'report';
const EXTRA_ARGS = process.argv.slice(4);

function parseArgs(args: string[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (let i = 0; i < args.length; i++) {
    if (args[i].startsWith('--') && args[i + 1] !== undefined && !args[i + 1].startsWith('--')) {
      out[args[i].slice(2)] = args[i + 1];
      i++;
    } else if (args[i].startsWith('--')) {
      out[args[i].slice(2)] = 'true';
    }
  }
  return out;
}

// ─── Mode: verify ─────────────────────────────────────────────────────────────

function modeVerify(state: GroundingState): GroundingState {
  const now = new Date().toISOString();
  console.log(`[GROUNDING] verify — ${state.assertions.length} assertions`);

  const updated: GroundingAssertion[] = [];
  for (const assertion of state.assertions) {
    process.stdout.write(`  [${assertion.id}] ${assertion.claim.slice(0, 60)}...`);
    const result = executeCheck(assertion.formal_check, REPO_ROOT);
    const pass = result.status === 'PASS';
    const confidence = pass ? assertion.base_confidence : Math.max(0, assertion.confidence * 0.5);

    const refreshed: GroundingAssertion = {
      ...assertion,
      last_check: result,
      last_verified_at: now,
      confidence,
    };
    const final = refreshStatus(refreshed);
    updated.push(final);
    console.log(` ${result.status} (${result.elapsed_ms.toFixed(0)}ms)`);
    if (result.status !== 'PASS' && result.observed) {
      console.log(`    observed: ${result.observed.slice(0, 120)}`);
    }
    if (result.error) {
      console.log(`    error: ${result.error.slice(0, 120)}`);
    }
  }

  const contradictions = detectContradictions(updated, state.contradictions);
  // Mark contradicting assertions
  for (const c of contradictions) {
    const a = updated.find(x => x.id === c.assertion_a);
    const b = updated.find(x => x.id === c.assertion_b);
    if (a) { a.contradiction_ids = [...(a.contradiction_ids ?? []), c.id]; a.status = 'CONTRADICTION'; }
    if (b) { b.contradiction_ids = [...(b.contradiction_ids ?? []), c.id]; b.status = 'CONTRADICTION'; }
  }

  return { ...state, assertions: updated, contradictions, last_full_verify: now };
}

// ─── Contradiction detection ──────────────────────────────────────────────────

function detectContradictions(assertions: GroundingAssertion[], existing: ContradictionSet[]): ContradictionSet[] {
  const all = [...existing];
  const existingPairs = new Set(existing.map(c => `${c.assertion_a}:${c.assertion_b}`));
  const now = new Date().toISOString();

  // Detect: same file_exists path, one PASS one FAIL
  const fileExists = assertions.filter(a => a.formal_check.type === 'file_exists' && a.last_check);
  for (let i = 0; i < fileExists.length; i++) {
    for (let j = i + 1; j < fileExists.length; j++) {
      const a = fileExists[i];
      const b = fileExists[j];
      if (a.formal_check.path !== b.formal_check.path) continue;
      const aPass = a.last_check?.status === 'PASS';
      const bPass = b.last_check?.status === 'PASS';
      if (aPass === bPass) continue;
      const pairKey = `${a.id}:${b.id}`;
      if (existingPairs.has(pairKey)) continue;
      const fakeState: GroundingState = { version: '1', assertions, contradictions: all };
      const cId = nextContradictionId(fakeState);
      all.push({
        id: cId,
        assertion_a: a.id,
        assertion_b: b.id,
        strategy: 'newer_wins',
        detected_at: now,
      });
      existingPairs.add(pairKey);
    }
  }

  // Detect: same git_state command, different expected
  const gitState = assertions.filter(a => a.formal_check.type === 'git_state' && a.last_check);
  for (let i = 0; i < gitState.length; i++) {
    for (let j = i + 1; j < gitState.length; j++) {
      const a = gitState[i];
      const b = gitState[j];
      if (a.formal_check.command !== b.formal_check.command) continue;
      if (a.last_check?.observed !== b.last_check?.observed) continue; // same state
      const aPass = a.last_check?.status === 'PASS';
      const bPass = b.last_check?.status === 'PASS';
      if (aPass === bPass) continue;
      const pairKey = `${a.id}:${b.id}`;
      if (existingPairs.has(pairKey)) continue;
      const fakeState: GroundingState = { version: '1', assertions, contradictions: all };
      const cId = nextContradictionId(fakeState);
      all.push({
        id: cId,
        assertion_a: a.id,
        assertion_b: b.id,
        strategy: 'higher_confidence_wins',
        detected_at: now,
      });
      existingPairs.add(pairKey);
    }
  }

  return all;
}

// ─── Mode: auto-generate ──────────────────────────────────────────────────────

function modeAutoGenerate(state: GroundingState): GroundingState {
  const { added, state: newState } = autoGenerate(state, REPO_ROOT);
  console.log(`[GROUNDING] auto-generate — added ${added.length} assertion(s)`);
  for (const a of added) {
    console.log(`  ${a.id}: [${a.source}] ${a.claim.slice(0, 80)}`);
  }
  return newState;
}

// ─── Mode: assert ─────────────────────────────────────────────────────────────

function modeAssert(state: GroundingState, args: Record<string, string>): GroundingState {
  const existingId = args.id;
  const claim = args.claim;
  const type = args.type as GroundingAssertion['formal_check']['type'] | undefined;

  if (!claim || !type) {
    console.error('[GROUNDING] assert: --claim and --type are required');
    process.exit(1);
  }

  const id = existingId ?? nextAssertionId(state);
  const existing = state.assertions.find(a => a.id === id);
  const baseConf = parseFloat(args.confidence ?? '0.8');

  const formalCheck: GroundingAssertion['formal_check'] = { type };
  if (args.command) formalCheck.command = args.command;
  if (args.expected) formalCheck.expected = args.expected;
  if (args.path) formalCheck.path = args.path;
  if (args.glob) formalCheck.glob = args.glob;
  if (args.pattern) formalCheck.pattern = args.pattern;
  if (args['invariant-id']) formalCheck.invariant_id = args['invariant-id'];
  if (args.timeout) formalCheck.timeout_ms = parseInt(args.timeout, 10);

  const newAssertion: GroundingAssertion = {
    ...(existing ?? {}),
    id,
    claim,
    formal_check: formalCheck,
    confidence: baseConf,
    base_confidence: baseConf,
    decay_half_life_hours: parseFloat(args['decay-hours'] ?? '48'),
    status: 'UNVERIFIED',
    source: 'manual',
    tags: args.tags ? args.tags.split(',') : (existing?.tags ?? []),
    created_at: existing?.created_at ?? new Date().toISOString(),
  };

  const assertions = existing
    ? state.assertions.map(a => a.id === id ? newAssertion : a)
    : [...state.assertions, newAssertion];

  console.log(`[GROUNDING] assert — ${existing ? 'updated' : 'added'} ${id}: ${claim.slice(0, 80)}`);
  return { ...state, assertions };
}

// ─── Mode: contradiction-resolve ─────────────────────────────────────────────

function modeContradictionResolve(state: GroundingState): GroundingState {
  const now = new Date().toISOString();
  const updatedContradictions: ContradictionSet[] = [];
  const resolvedAssertionIds = new Set<string>();

  for (const c of state.contradictions) {
    if (c.resolved_at) { updatedContradictions.push(c); continue; }

    const a = state.assertions.find(x => x.id === c.assertion_a);
    const b = state.assertions.find(x => x.id === c.assertion_b);
    if (!a || !b) { updatedContradictions.push(c); continue; }

    let winner: string | undefined;
    let reason: string | undefined;

    switch (c.strategy) {
      case 'newer_wins': {
        const ta = a.last_verified_at ? new Date(a.last_verified_at).getTime() : 0;
        const tb = b.last_verified_at ? new Date(b.last_verified_at).getTime() : 0;
        winner = ta >= tb ? a.id : b.id;
        reason = `newer_wins: ${winner} verified at ${winner === a.id ? a.last_verified_at : b.last_verified_at}`;
        break;
      }
      case 'higher_confidence_wins': {
        winner = a.confidence >= b.confidence ? a.id : b.id;
        reason = `higher_confidence_wins: ${winner} conf=${winner === a.id ? a.confidence : b.confidence}`;
        break;
      }
      case 'require_human':
        winner = undefined;
        reason = 'requires human resolution';
        break;
    }

    console.log(`[GROUNDING] contradiction ${c.id}: ${a.id} vs ${b.id} — ${reason ?? 'pending'}`);
    updatedContradictions.push({ ...c, resolved_at: winner ? now : undefined, winner, reason });
    if (winner) resolvedAssertionIds.add(winner === a.id ? b.id : a.id);
  }

  // Clear contradiction status for resolved assertions
  const updatedAssertions = state.assertions.map(a => {
    if (!resolvedAssertionIds.has(a.id)) return a;
    const cleared = { ...a, contradiction_ids: [] };
    return refreshStatus(cleared);
  });

  return { ...state, assertions: updatedAssertions, contradictions: updatedContradictions };
}

// ─── Mode: report ─────────────────────────────────────────────────────────────

function modeReport(state: GroundingState): void {
  const metrics = computeMetrics(state);
  const grade = scoreGrade(metrics.composite_score);

  console.log('[GROUNDING] Grounding Verification Report');
  console.log('─'.repeat(60));
  console.log(`  Composite Score : ${(metrics.composite_score * 100).toFixed(1)}%  (${grade})`);
  console.log(`  Coverage        : ${(metrics.coverage * 100).toFixed(1)}%  (${metrics.verified_count}/${metrics.total_assertions} assertions verified)`);
  console.log(`  Accuracy        : ${(metrics.accuracy * 100).toFixed(1)}%  (checks passing)`);
  console.log(`  Staleness       : ${(metrics.staleness * 100).toFixed(1)}%  (mean decay)`);
  if (metrics.contradiction_count > 0) {
    console.log(`  Contradictions  : ${metrics.contradiction_count} (resolve with contradiction-resolve mode)`);
  }
  if (metrics.gap_declared) {
    console.log(`  STATUS          : GROUNDING GAP — score ${(metrics.composite_score * 100).toFixed(1)}% < ${(GROUNDING_THRESHOLD * 100).toFixed(0)}% threshold`);
  } else {
    console.log(`  STATUS          : GROUNDED`);
  }
  console.log('─'.repeat(60));

  // Per-assertion summary
  if (state.assertions.length > 0) {
    console.log('  Assertions:');
    for (const a of state.assertions.map(x => refreshStatus({ ...x }))) {
      const decay = decayFraction(a.last_verified_at, a.decay_half_life_hours);
      const icon = a.status === 'GROUNDED' ? '✓' : a.status === 'FAILED' ? '✗' : a.status === 'CONTRADICTION' ? '!' : a.status === 'STALE' ? '~' : '?';
      const conf = `${(a.confidence * 100).toFixed(0)}%`;
      const stale = `decay=${(decay * 100).toFixed(0)}%`;
      console.log(`    ${icon} ${a.id}  ${a.claim.slice(0, 55).padEnd(55)}  [${a.status.padEnd(13)}] conf=${conf} ${stale}`);
    }
  }
}

// ─── Mode: score ──────────────────────────────────────────────────────────────

function modeScore(state: GroundingState): void {
  const metrics = computeMetrics(state);
  // Machine-readable: just the score
  console.log(metrics.composite_score.toFixed(4));
}

// ─── Report writer ────────────────────────────────────────────────────────────

function writeReport(state: GroundingState): void {
  const metrics = computeMetrics(state);
  const out = {
    generated_at: new Date().toISOString(),
    metrics,
    assertions: state.assertions.map(a => {
      const r = refreshStatus({ ...a });
      return {
        id: r.id,
        claim: r.claim,
        status: r.status,
        confidence: r.confidence,
        last_verified_at: r.last_verified_at,
        last_check: r.last_check,
        source: r.source,
        tags: r.tags,
      };
    }),
    contradictions: state.contradictions,
  };
  const fp = path.join(REPO_ROOT, REPORT_FILE);
  try {
    fs.mkdirSync(path.dirname(fp), { recursive: true });
    fs.writeFileSync(fp, JSON.stringify(out, null, 2).replace(/\r\n/g, '\n'), 'utf8');
  } catch { /* non-fatal */ }
}

// ─── Main ─────────────────────────────────────────────────────────────────────

function main(): void {
  let state = loadState(REPO_ROOT);
  const args = parseArgs(EXTRA_ARGS);

  switch (MODE) {
    case 'verify': {
      state = modeVerify(state);
      saveState(state, REPO_ROOT);
      writeReport(state);
      const metrics = computeMetrics(state);
      console.log(`\n[GROUNDING] score=${(metrics.composite_score * 100).toFixed(1)}% gap=${metrics.gap_declared}`);
      if (metrics.gap_declared) {
        console.log(`[GROUNDING] WARN: grounding gap — score ${(metrics.composite_score * 100).toFixed(1)}% < ${(GROUNDING_THRESHOLD * 100).toFixed(0)}%`);
        // Advisory only — no exit 1 (operators must explicitly gate on score)
      }
      break;
    }
    case 'auto-generate': {
      state = modeAutoGenerate(state);
      saveState(state, REPO_ROOT);
      const metrics = computeMetrics(state);
      console.log(`[GROUNDING] state: ${state.assertions.length} total assertions, score=${(metrics.composite_score * 100).toFixed(1)}%`);
      break;
    }
    case 'assert': {
      state = modeAssert(state, args);
      saveState(state, REPO_ROOT);
      break;
    }
    case 'report': {
      modeReport(state);
      writeReport(state);
      break;
    }
    case 'score': {
      modeScore(state);
      break;
    }
    case 'contradiction-resolve': {
      state = modeContradictionResolve(state);
      saveState(state, REPO_ROOT);
      modeReport(state);
      writeReport(state);
      break;
    }
    default:
      console.error(`[GROUNDING] unknown mode: ${MODE}`);
      console.error('  modes: verify | auto-generate | assert | report | score | contradiction-resolve');
      process.exit(1);
  }
}

main();
