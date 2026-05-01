# /simulate-change

**Change Simulation Protocol** — forward simulation before implementation in **Build** (or stricter) modes. Answers three questions **without writing** tracked source files:

1. **Contract delta** — exported functions / interfaces / types: additive, breaking, or neutral? (`simulate-contract-delta.cjs`, TypeScript Compiler API surface)
2. **Blast radius** — who imports the seeds, transitively, which tests touch the closure? (`.claude/knowledge-graph.json`)
3. **Invariant impact** — which entries in `.claude/invariants.json` scopes overlap the touched paths? (`AT_RISK` / `MONITOR`)

## Prerequisites

- `node` on PATH.
- `typescript` devDependency in the consumer repo **or** run from a clone where `templates/invariant-engine/node_modules` exists (OS development).
- Knowledge graph for blast radius: `bash .claude/scripts/knowledge-graph.sh --build` if `.claude/knowledge-graph.json` is missing or stale.

## Command

```bash
bash .claude/scripts/change-simulation.sh \
  --change "add orgId to Session type" \
  --baseline shared/types/auth.ts \
  --proposed /path/to/auth.proposed.ts \
  --files "shared/types/auth.ts,server/auth/index.ts,client/hooks/useAuth.ts"
```

- **`--change`**: one-line human description (required for the report header).
- **`--baseline` / `--proposed`**: optional pair; both must be set to run contract delta. The **proposed** path is typically a scratch copy (editor buffer written to `/tmp` or `.local/`) — it does **not** replace the baseline in git.
- **`--files`**: comma-separated repo-relative paths used as **seeds** for blast-radius and invariant scope matching (include primary modules even if you only pass baseline/proposed for one file).

## Artefacts

- **Stdout**: `[OS-SIMULATION]` narrative (contract summary, blast radius counts, invariants at risk, heuristic recommendation).
- **`.claude/simulation-report.json`**: machine-readable bundle (`contract_delta`, `blast_radius`, `invariants_at_risk`).

## Rules

- Simulation **informs**; it does not replace tests, review, or human gates.
- If contract delta reports **BREAKING**, sequence work (additive → migrate callers → tighten) unless risk is explicitly accepted and recorded.
- Re-run after materially changing the plan or the proposed snapshot.
