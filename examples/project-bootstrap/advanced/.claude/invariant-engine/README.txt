When invariant-engine bundles are present in the Claude OS repo at init time, init-project copies:

  invariant-engine.cjs
  semantic-diff.cjs
  simulate-contract-delta.cjs

into .claude/invariant-engine/

If missing, init-project prints a warning; build from templates/invariant-engine (npm install && npm run build).
