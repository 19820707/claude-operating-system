/**
 * Grounding metrics computation.
 * Composite score = Coverage × Accuracy × (1 - Staleness_normalized)
 * Staleness uses exponential decay from last_verified_at and decay_half_life_hours.
 */

import { GroundingAssertion, GroundingMetrics, GroundingState, GROUNDING_THRESHOLD, STALE_THRESHOLD } from './types.js';

const LN2 = Math.LN2;

/**
 * Compute exponential decay fraction [0,1].
 * Returns 0 if just verified, approaches 1 as time passes.
 * Half-life: elapsed_hours = half_life → decay = 0.5
 */
export function decayFraction(lastVerifiedAt: string | undefined, halfLifeHours: number): number {
  if (!lastVerifiedAt) return 1.0;
  const elapsedMs = Date.now() - new Date(lastVerifiedAt).getTime();
  if (elapsedMs <= 0) return 0.0;
  const elapsedHours = elapsedMs / (1000 * 3600);
  const lambda = LN2 / Math.max(0.1, halfLifeHours);
  return 1 - Math.exp(-lambda * elapsedHours);
}

/** Current effective confidence after decay. */
export function effectiveConfidence(a: GroundingAssertion): number {
  const decay = decayFraction(a.last_verified_at, a.decay_half_life_hours);
  return a.base_confidence * (1 - decay);
}

/**
 * Refresh assertion status based on decay.
 * Mutates in place; returns the same object.
 */
export function refreshStatus(a: GroundingAssertion): GroundingAssertion {
  const eff = effectiveConfidence(a);
  const decayFrac = decayFraction(a.last_verified_at, a.decay_half_life_hours);
  if (a.contradiction_ids && a.contradiction_ids.length > 0) {
    a.status = 'CONTRADICTION';
  } else if (!a.last_check || a.last_check.status === 'SKIP') {
    a.status = 'UNVERIFIED';
  } else if (a.last_check.status !== 'PASS') {
    a.status = 'FAILED';
  } else if (decayFrac >= STALE_THRESHOLD) {
    a.status = 'STALE';
  } else {
    a.status = 'GROUNDED';
  }
  a.confidence = Math.max(0, eff);
  return a;
}

/** Compute composite grounding metrics for the full state. */
export function computeMetrics(state: GroundingState): GroundingMetrics {
  const assertions = state.assertions.map(a => refreshStatus({ ...a }));
  const total = assertions.length;
  if (total === 0) {
    const empty: GroundingMetrics = {
      total_assertions: 0,
      verified_count: 0,
      coverage: 0,
      accuracy: 0,
      staleness: 1,
      composite_score: 0,
      gap_declared: true,
      contradiction_count: 0,
      computed_at: new Date().toISOString(),
    };
    return empty;
  }

  // Verified = has a last_check that is not SKIP
  const verified = assertions.filter(a => a.last_check && a.last_check.status !== 'SKIP');
  const passed = verified.filter(a => a.last_check!.status === 'PASS');
  const coverage = total > 0 ? verified.length / total : 0;
  const accuracy = verified.length > 0 ? passed.length / verified.length : 0;

  // Staleness: mean decay fraction across all assertions
  const meanStaleness = total > 0
    ? assertions.reduce((sum, a) => sum + decayFraction(a.last_verified_at, a.decay_half_life_hours), 0) / total
    : 1.0;

  const composite = coverage * accuracy * (1 - meanStaleness);
  const contradictions = assertions.filter(a => a.status === 'CONTRADICTION').length;

  return {
    total_assertions: total,
    verified_count: verified.length,
    coverage: round4(coverage),
    accuracy: round4(accuracy),
    staleness: round4(meanStaleness),
    composite_score: round4(composite),
    gap_declared: composite < GROUNDING_THRESHOLD,
    contradiction_count: contradictions,
    computed_at: new Date().toISOString(),
  };
}

function round4(n: number): number {
  return Math.round(n * 10000) / 10000;
}

/** Human-readable score interpretation. */
export function scoreGrade(score: number): string {
  if (score >= 0.85) return 'A — highly grounded';
  if (score >= 0.70) return 'B — well grounded';
  if (score >= 0.60) return 'C — adequately grounded';
  if (score >= 0.45) return 'D — grounding gap present';
  return 'F — critical grounding gap';
}
