/**
 * State persistence for grounding-state.json.
 * Atomic write via temp-file rename; LF-only output.
 */

import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import * as crypto from 'crypto';
import { GroundingState, STATE_FILE } from './types.js';

const SCHEMA_VERSION = '1' as const;

export function loadState(repoRoot: string): GroundingState {
  const fp = path.join(repoRoot, STATE_FILE);
  if (!fs.existsSync(fp)) {
    return emptyState();
  }
  try {
    const raw = fs.readFileSync(fp, 'utf8');
    const parsed = JSON.parse(raw) as Partial<GroundingState>;
    return {
      version: SCHEMA_VERSION,
      assertions: Array.isArray(parsed.assertions) ? parsed.assertions : [],
      contradictions: Array.isArray(parsed.contradictions) ? parsed.contradictions : [],
      metrics: parsed.metrics,
      last_full_verify: parsed.last_full_verify,
      auto_generated_at: parsed.auto_generated_at,
    };
  } catch {
    return emptyState();
  }
}

export function saveState(state: GroundingState, repoRoot: string): void {
  const fp = path.join(repoRoot, STATE_FILE);
  const dir = path.dirname(fp);
  fs.mkdirSync(dir, { recursive: true });
  const content = JSON.stringify(state, null, 2).replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  // Atomic write: temp file then rename
  const tmp = path.join(os.tmpdir(), `grounding-${crypto.randomBytes(6).toString('hex')}.json`);
  fs.writeFileSync(tmp, content, { encoding: 'utf8' });
  try {
    fs.renameSync(tmp, fp);
  } catch {
    // Fallback: cross-device rename fails on some systems
    fs.copyFileSync(tmp, fp);
    try { fs.unlinkSync(tmp); } catch { /* ignore */ }
  }
}

export function emptyState(): GroundingState {
  return { version: SCHEMA_VERSION, assertions: [], contradictions: [] };
}

/** Generate a stable, collision-resistant assertion ID. */
export function nextAssertionId(existing: GroundingState): string {
  const current = new Set(existing.assertions.map(a => a.id));
  let n = existing.assertions.length + 1;
  while (current.has(`GRND-${String(n).padStart(3, '0')}`)) n++;
  return `GRND-${String(n).padStart(3, '0')}`;
}

/** Generate a contradiction ID. */
export function nextContradictionId(existing: GroundingState): string {
  const current = new Set(existing.contradictions.map(c => c.id));
  let n = existing.contradictions.length + 1;
  while (current.has(`CONTR-${String(n).padStart(3, '0')}`)) n++;
  return `CONTR-${String(n).padStart(3, '0')}`;
}
