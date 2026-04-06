# /hardening-pass

**Model:** Sonnet
**Mode:** Fast (non-critical surfaces) → Critical if auth/billing/publish touched

Perform a low-risk hardening pass:
1. validation strengthening — tighten input/output contracts
2. defensive handling — explicit error paths, no silent failures
3. logging improvements — structured audit events on key paths
4. test reinforcement — add missing negative/failure-path tests

**Rules:**
- no functional changes — harden only, do not refactor
- validate after each change: typecheck + targeted tests
- if a hardening change touches a critical surface → stop and escalate
- show diff + checks before closing
