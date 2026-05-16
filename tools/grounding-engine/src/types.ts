/**
 * Grounding Verification Engine — type system.
 * Formal proof obligations over OS assertions; not a heuristic dictionary.
 */

export type CheckType =
  | 'git_state'
  | 'file_exists'
  | 'pattern_absent'
  | 'invariant_holds'
  | 'external_query';

export type CheckStatus = 'PASS' | 'FAIL' | 'SKIP' | 'TIMEOUT' | 'ERROR';

export type GroundingStatus =
  | 'GROUNDED'     // last check passed and within staleness window
  | 'UNVERIFIED'   // never checked or check timed out
  | 'FAILED'       // last check failed
  | 'STALE'        // confidence decayed below STALE_THRESHOLD
  | 'CONTRADICTION'; // conflicts with another assertion

export type ResolutionStrategy =
  | 'newer_wins'
  | 'higher_confidence_wins'
  | 'require_human';

export type AssertionSource =
  | 'manual'
  | 'auto-world-model'
  | 'auto-epistemic'
  | 'auto-invariant'
  | 'auto-session';

export interface FormalCheck {
  type: CheckType;
  /** git_state / external_query: shell command to run from repo root */
  command?: string;
  /** git_state / external_query / pattern_absent: expected substring in stdout OR regex pattern that must be absent */
  expected?: string;
  /** file_exists / pattern_absent: path or glob (relative to repo root) */
  path?: string;
  /** pattern_absent: glob pattern to select files */
  glob?: string;
  /** pattern_absent: regex that must NOT appear in matching files */
  pattern?: string;
  /** invariant_holds: invariant ID (INV-xxx) from invariant-report.json */
  invariant_id?: string;
  /** max execution time in ms (default 5000) */
  timeout_ms?: number;
}

export interface CheckResult {
  type: CheckType;
  status: CheckStatus;
  observed?: string;
  expected?: string;
  elapsed_ms: number;
  error?: string;
}

export interface GroundingAssertion {
  id: string;
  claim: string;
  formal_check: FormalCheck;
  /** Current confidence [0,1]; decays over time */
  confidence: number;
  /** Initial / reset confidence; used to restore after successful re-check */
  base_confidence: number;
  last_verified_at?: string;
  last_check?: CheckResult;
  /** Exponential decay: half-life in hours */
  decay_half_life_hours: number;
  status: GroundingStatus;
  source: AssertionSource;
  contradiction_ids?: string[];
  tags?: string[];
  created_at: string;
}

export interface ContradictionSet {
  id: string;
  assertion_a: string;
  assertion_b: string;
  strategy: ResolutionStrategy;
  detected_at: string;
  resolved_at?: string;
  winner?: string;
  reason?: string;
}

export interface GroundingMetrics {
  total_assertions: number;
  verified_count: number;
  /** verified_count / total_assertions */
  coverage: number;
  /** assertions with PASS check / verified_count */
  accuracy: number;
  /** mean normalized staleness [0,1] */
  staleness: number;
  /** Coverage × Accuracy × (1 - staleness) */
  composite_score: number;
  /** composite_score < GROUNDING_THRESHOLD */
  gap_declared: boolean;
  contradiction_count: number;
  computed_at: string;
}

export interface GroundingState {
  version: '1';
  assertions: GroundingAssertion[];
  contradictions: ContradictionSet[];
  metrics?: GroundingMetrics;
  last_full_verify?: string;
  auto_generated_at?: string;
}

export const GROUNDING_THRESHOLD = 0.6;
export const STALE_THRESHOLD = 0.8;   // confidence decay fraction at which assertion is STALE
export const STATE_FILE = '.claude/grounding-state.json';
export const REPORT_FILE = '.claude/grounding-report.json';
