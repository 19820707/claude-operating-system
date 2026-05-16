/**
 * Auto-generation of grounding assertions from existing OS artifacts.
 * Sources: world-model.json, epistemic-state.json, invariants/core.json, session-state.md
 */

import * as fs from 'fs';
import * as path from 'path';
import { GroundingAssertion, GroundingState, AssertionSource } from './types.js';
import { nextAssertionId } from './state.js';

const NOW = new Date().toISOString();
const CLAUDE_DIR = '.claude';
const TEMPLATE_INVARIANTS = 'templates/invariants/core.json';

// ─── Source: world-model.json ─────────────────────────────────────────────────

interface WorldEntity {
  id: string;
  type: string;
  path?: string;
  risk?: number;
  confidence?: number;
}

interface WorldModel {
  entities?: WorldEntity[];
  global_state?: { branch?: string };
}

function fromWorldModel(repoRoot: string, state: GroundingState): GroundingAssertion[] {
  const fp = path.join(repoRoot, CLAUDE_DIR, 'world-model.json');
  if (!fs.existsSync(fp)) return [];
  let wm: WorldModel;
  try { wm = JSON.parse(fs.readFileSync(fp, 'utf8')); } catch { return []; }

  const results: GroundingAssertion[] = [];
  const existingPaths = new Set(
    state.assertions
      .filter(a => a.formal_check.type === 'file_exists' && a.source === 'auto-world-model')
      .map(a => a.formal_check.path ?? '')
  );

  // Generate file_exists for high-risk file entities
  for (const entity of (wm.entities ?? [])) {
    if (entity.type !== 'file') continue;
    if (!entity.path) continue;
    if ((entity.risk ?? 0) < 0.3) continue; // only medium+ risk files
    if (existingPaths.has(entity.path)) continue;

    const id = nextAssertionId({ ...state, assertions: [...state.assertions, ...results] });
    results.push({
      id,
      claim: `High-risk file exists: ${entity.path}`,
      formal_check: { type: 'file_exists', path: entity.path },
      confidence: entity.confidence ?? 0.8,
      base_confidence: entity.confidence ?? 0.8,
      decay_half_life_hours: 48,
      status: 'UNVERIFIED',
      source: 'auto-world-model',
      tags: ['world-model', 'file', `risk:${((entity.risk ?? 0) * 100).toFixed(0)}`],
      created_at: NOW,
    });
  }

  // Generate git_state assertion for known branch
  const branch = wm.global_state?.branch;
  if (branch && !state.assertions.some(a => a.source === 'auto-world-model' && a.formal_check.type === 'git_state' && a.claim.includes('branch'))) {
    const id = nextAssertionId({ ...state, assertions: [...state.assertions, ...results] });
    results.push({
      id,
      claim: `Repository is on branch: ${branch}`,
      formal_check: { type: 'git_state', command: 'git rev-parse --abbrev-ref HEAD', expected: branch },
      confidence: 0.9,
      base_confidence: 0.9,
      decay_half_life_hours: 6,
      status: 'UNVERIFIED',
      source: 'auto-world-model',
      tags: ['world-model', 'git', 'branch'],
      created_at: NOW,
    });
  }

  return results;
}

// ─── Source: epistemic-state.json ─────────────────────────────────────────────

interface EpistemicFact {
  key: string;
  value: string;
  status: string;
  confidence: number;
  category?: string;
  tags?: string[];
  last_updated?: string;
}

interface EpistemicState {
  facts?: Record<string, EpistemicFact>;
}

function fromEpistemicState(repoRoot: string, state: GroundingState): GroundingAssertion[] {
  const fp = path.join(repoRoot, CLAUDE_DIR, 'epistemic-state.json');
  if (!fs.existsSync(fp)) return [];
  let es: EpistemicState;
  try { es = JSON.parse(fs.readFileSync(fp, 'utf8')); } catch { return []; }

  const results: GroundingAssertion[] = [];
  const existingKeys = new Set(
    state.assertions
      .filter(a => a.source === 'auto-epistemic')
      .map(a => a.tags?.find(t => t.startsWith('fact:'))?.slice(5) ?? '')
  );

  for (const [key, fact] of Object.entries(es.facts ?? {})) {
    if (existingKeys.has(key)) continue;
    // Only assert known facts with reasonable confidence
    if (fact.status !== 'KNOWN' || fact.confidence < 0.6) continue;
    // Map fact category to a formal check
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
      status: 'UNVERIFIED',
      source: 'auto-epistemic',
      tags: ['epistemic', `fact:${key}`, ...(fact.tags ?? [])],
      created_at: NOW,
    });
  }

  return results;
}

function buildEpistemicCheck(key: string, fact: EpistemicFact): GroundingAssertion['formal_check'] | null {
  // exit_code facts: verify the file exists
  if (key.startsWith('exit_code:')) {
    const filePart = key.slice('exit_code:'.length);
    const filePath = filePart.replace(/\./g, '/').replace(/\/ps1$/, '.ps1');
    return { type: 'file_exists', path: filePath };
  }
  // branch fact
  if (key === 'repo.branch' && fact.value) {
    return { type: 'git_state', command: 'git rev-parse --abbrev-ref HEAD', expected: String(fact.value) };
  }
  // General: skip — no safe general mapping
  return null;
}

// ─── Source: templates/invariants/core.json ────────────────────────────────────

interface InvariantSpec {
  id: string;
  name: string;
  status?: string;
  violation_severity?: string;
}

function fromInvariants(repoRoot: string, state: GroundingState): GroundingAssertion[] {
  const fp = path.join(repoRoot, TEMPLATE_INVARIANTS);
  if (!fs.existsSync(fp)) return [];
  let raw: unknown;
  try { raw = JSON.parse(fs.readFileSync(fp, 'utf8')); } catch { return []; }

  const specs: InvariantSpec[] = [];
  if (Array.isArray(raw)) {
    specs.push(...(raw as InvariantSpec[]));
  } else if (raw && typeof raw === 'object' && Array.isArray((raw as { invariants?: unknown }).invariants)) {
    specs.push(...((raw as { invariants: InvariantSpec[] }).invariants));
  }

  const results: GroundingAssertion[] = [];
  const existingInvIds = new Set(
    state.assertions
      .filter(a => a.source === 'auto-invariant')
      .map(a => a.formal_check.invariant_id ?? '')
  );

  for (const spec of specs) {
    if (!spec.id) continue;
    if (spec.status === 'DEPRECATED' || spec.status === 'INACTIVE') continue;
    if (existingInvIds.has(spec.id)) continue;

    const severity = spec.violation_severity ?? 'WARN';
    const baseConf = severity === 'CRITICAL' ? 0.95 : severity === 'HIGH' ? 0.85 : 0.75;
    const id = nextAssertionId({ ...state, assertions: [...state.assertions, ...results] });
    results.push({
      id,
      claim: `Invariant ${spec.id} holds: ${spec.name}`,
      formal_check: { type: 'invariant_holds', invariant_id: spec.id },
      confidence: baseConf,
      base_confidence: baseConf,
      decay_half_life_hours: 72,
      status: 'UNVERIFIED',
      source: 'auto-invariant',
      tags: ['invariant', spec.id, `severity:${severity}`],
      created_at: NOW,
    });
  }
  return results;
}

// ─── Source: session-state.md ─────────────────────────────────────────────────

function fromSessionState(repoRoot: string, state: GroundingState): GroundingAssertion[] {
  const fp = path.join(repoRoot, CLAUDE_DIR, 'session-state.md');
  if (!fs.existsSync(fp)) return [];
  let text = '';
  try { text = fs.readFileSync(fp, 'utf8'); } catch { return []; }

  const results: GroundingAssertion[] = [];

  // Assert session-state.md is not stale (no explicit staleness markers needed — just verify file exists)
  const hasSessionAssertion = state.assertions.some(
    a => a.source === 'auto-session' && a.formal_check.type === 'file_exists' && a.formal_check.path === `${CLAUDE_DIR}/session-state.md`
  );
  if (!hasSessionAssertion) {
    const id = nextAssertionId({ ...state, assertions: [...state.assertions, ...results] });
    results.push({
      id,
      claim: 'Session state file exists and is maintained',
      formal_check: { type: 'file_exists', path: `${CLAUDE_DIR}/session-state.md` },
      confidence: 1.0,
      base_confidence: 1.0,
      decay_half_life_hours: 12,
      status: 'UNVERIFIED',
      source: 'auto-session',
      tags: ['session', 'continuity'],
      created_at: NOW,
    });
  }

  // Assert learning-log.md exists
  const hasLearningAssertion = state.assertions.some(
    a => a.source === 'auto-session' && a.formal_check.path === `${CLAUDE_DIR}/learning-log.md`
  );
  if (!hasLearningAssertion) {
    const id = nextAssertionId({ ...state, assertions: [...state.assertions, ...results] });
    results.push({
      id,
      claim: 'Learning log exists (phase continuity)',
      formal_check: { type: 'file_exists', path: `${CLAUDE_DIR}/learning-log.md` },
      confidence: 0.9,
      base_confidence: 0.9,
      decay_half_life_hours: 24,
      status: 'UNVERIFIED',
      source: 'auto-session',
      tags: ['session', 'learning-log'],
      created_at: NOW,
    });
  }

  // Assert no PSDrive pattern in tools (H16 guard)
  const hasH16Assertion = state.assertions.some(
    a => a.source === 'auto-session' && a.tags?.includes('H16')
  );
  if (!hasH16Assertion) {
    const id = nextAssertionId({ ...state, assertions: [...state.assertions, ...results] });
    results.push({
      id,
      claim: 'No unbraced PS variable followed by colon in tools/ (H16 invariant)',
      formal_check: {
        type: 'pattern_absent',
        glob: 'tools/**/*.ps1',
        pattern: '"[^"]*\\$[A-Za-z][A-Za-z0-9_]*:[^:]',
      },
      confidence: 0.95,
      base_confidence: 0.95,
      decay_half_life_hours: 120,
      status: 'UNVERIFIED',
      source: 'auto-session',
      tags: ['session', 'H16', 'powershell', 'invariant'],
      created_at: NOW,
    });
  }

  return results;
}

// ─── Entry point ───────────────────────────────────────────────────────────────

export function autoGenerate(state: GroundingState, repoRoot: string): {
  added: GroundingAssertion[];
  state: GroundingState;
} {
  const added: GroundingAssertion[] = [];

  const wm = fromWorldModel(repoRoot, state);
  added.push(...wm);
  const s1: GroundingState = { ...state, assertions: [...state.assertions, ...added] };

  const ep = fromEpistemicState(repoRoot, s1);
  added.push(...ep);
  const s2: GroundingState = { ...state, assertions: [...state.assertions, ...added] };

  const inv = fromInvariants(repoRoot, s2);
  added.push(...inv);
  const s3: GroundingState = { ...state, assertions: [...state.assertions, ...added] };

  const sess = fromSessionState(repoRoot, s3);
  added.push(...sess);

  const finalState: GroundingState = {
    ...state,
    assertions: [...state.assertions, ...added],
    auto_generated_at: NOW,
  };

  return { added, state: finalState };
}
