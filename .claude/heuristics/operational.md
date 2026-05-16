# Heuristics — Operational

Promoted patterns from real project evidence.
Each entry: evidence observed → rule → how to apply.
Update when a new pattern is confirmed across at least one real incident.

---

## Environment & Tooling

### H1 — Windows + core.autocrlf=true contaminates working tree after stash

**Evidence:** `git stash --include-untracked` + `git checkout stash -- .` applied CRLF to all text files. Tests failed on `no CR bytes` assertions. Not regressions — CRLF artefacts.
**Rule:** On Windows with `core.autocrlf=true`, never use stash for working tree recovery. Prefer granular `git checkout -- <file>`.
**Apply:** Before any stash on Windows, run `git config core.autocrlf`. If `true`, avoid stash and document the alternative.

---

### H2 — IDE (Cursor/Copilot) can auto-commit working tree during active session

**Evidence:** Auto-commit created while session was running — included 500+ files, CRLF-contaminated, and in-progress manual changes not yet committed.
**Rule:** Before committing, always check `git log --oneline -3` for unexpected commits. Never assume HEAD is the last manual commit.
**Apply:** At the start of any git operation, confirm HEAD. If auto-commit detected, audit what entered before continuing.

---

### H5 — `git diff --ignore-cr-at-eol` distinguishes real diff from CRLF noise

**Evidence:** File showed as `M` in `git status` but `git diff HEAD <file>` showed only a CRLF warning with no content. `git diff --ignore-cr-at-eol HEAD <file> | wc -l` → 0. Zero real diff confirmed.
**Rule:** On Windows, before committing a "modified" file, check `git diff --ignore-cr-at-eol`. If empty → CRLF noise only, content identical to HEAD.
**Apply:** Add to phase-close checklist: if `git status` shows M but `git diff` shows no content → verify CRLF before committing.

---

### H10 — Write tool on Windows produces CRLF; use node.js to force LF

**Evidence:** Write tool wrote a file with CRLF. `no CR bytes` test failed. Fixed with `node -e "fs.writeFileSync(path, lines.join('\n'), {encoding:'utf8'})"`.
**Rule:** On Windows, for files that must have LF (`.gitignore`, scripts, policy files), use node.js with explicit `join('\n')` instead of the Write tool directly.
**Apply:** Files with line-ending tests → always write via node.js script. Regular files → Write tool is sufficient.

---

### H16 — PowerShell drive-prefix ambiguity: `"$var:"` is parsed as a PSDrive reference, not variable + colon

**Evidence:** `"$Name: invocation error..."` and `"$n: transitive blast=..."` in double-quoted strings caused `ParserError` at runtime. PowerShell parses `$identifier:` as a PSDrive reference (like `$env:`, `$HKLM:`), not as `$identifier` followed by a literal colon. The parser fails silently or throws depending on whether a provider with that name exists.
**Rule:** In any double-quoted PowerShell string, never write `"$varname: text"`. Always brace the variable: `"${varname}: text"`. This applies to all identifiers regardless of length — `$Name:`, `$n:`, `$tool:`, `$path:`.
**Apply:** When writing PS1 tools, grep for `"\$[A-Za-z][A-Za-z0-9_]*:` (unbraced var followed by colon in string). Fix every match. INV-012 formalises this invariant. Add to PR checklist for any `.ps1` file.

---

### H17 — CI Manifest Cascade: every new `tools/*.ps1` requires updates in 4 manifests

**Evidence:** Adding 5 tools in one session triggered `verify-components` failure (`universe item not mapped`) and `verify-script-manifest` warnings — both caused by manifest entries not being created for new tools. The cascade: `script-manifest.json` (tool metadata) → `component-manifest.json` (component membership) → `compatibility-manifest.json` (version compat) → `os-capabilities.json` (capability registry). Missing any one causes a different verifier to fail.
**Rule:** After adding any `tools/*.ps1`, run `pwsh ./tools/sync-manifests.ps1` immediately — it auto-registers in script-manifest and component-manifest. Then confirm `verify-script-manifest` and `verify-components` pass before staging the commit. Never commit a new tool without running sync-manifests first.
**Apply:** The pre-commit hook (`templates/hooks/pre-commit`) enforces this automatically. For manual commits, run `pwsh ./tools/sync-manifests.ps1 && pwsh ./tools/verify-script-manifest.ps1` before `git add`. If `verify-components` still fails, the policy file mapping is missing — add it to component-manifest manually via PowerShell object model (not Edit, to avoid CRLF).

---

### H15 — PowerShell `$null -ne 0` is `True`: scripts without `exit 0` propagate stale `$LASTEXITCODE`

**Evidence:** `verify-agent-adapters.ps1` succeeded but had no `exit 0`. After calling it via `&`, `$LASTEXITCODE` stayed `$null`. `sync-agent-adapters.ps1` then evaluated `$null -ne 0` → `True` (PowerShell null comparison semantics) → falsely treated a successful step as failed → exited 1. Similarly, `os-doctor.ps1` only had `exit 0` inside the `-Json` branch; the non-Json path fell off the end, leaving `$LASTEXITCODE` stale at 1 from the prior call. This triggered a cascade: `init-os-runtime.ps1` → `runtime-dispatcher` health check → CI failure.
**Rule:** Every `tools/*.ps1` that has any failure path (`exit 1`, `throw`, `exit [int]$code`) must have an explicit `exit 0` at the end of its success path. Do not assume a script that "runs fine" leaves `$LASTEXITCODE=0` — it only does if `exit 0` is called explicitly.
**Apply:** Run `pwsh ./tools/verify-exit-codes.ps1` before committing new tools scripts. Add `exit 0` as the last line of any script with a failure path. INV-011 formalises this invariant.

---

## Security & Validation

### H3 — Transitive DB imports break in test/middleware load

**Evidence:** Importing a utility from a module that transitively imports `db.ts` caused failure at module load — `DATABASE_URL` required but absent in test/middleware context.
**Rule:** In middleware and unit tests, never import from modules with transitive DB dependencies. Prefer inline functions or pure utilities without I/O.
**Apply:** Before adding an import in middleware/test, trace the chain: `module → imports → their imports`. If DB appears → inline or extract a pure utility.

---

### H4 — Inline sensitive utility is safer than shared import in critical contexts

**Evidence:** Inlining `createHash("sha256").update(id).digest("hex").slice(0,16)` directly avoided the H3 transitive DB problem and maintained the redaction contract without dependencies.
**Rule:** For simple, security-critical operations (hashing, redaction, sanitization), prefer inline over shared utility import when that utility has non-trivial dependencies.
**Apply:** Evaluate: (inline complexity) vs (transitive import risk). For SHA-256 truncation — inline is always preferable.

---

### H6 — Inclusive vs exclusive boundary is a security decision

**Evidence:** Validation used `< 0` (allowed 0). Corrected to `<= 0` (rejects 0). Zero silently disables the protection mechanism — fail-open by misconfiguration.
**Rule:** In security limit validations, always explicitly decide if the boundary is inclusive or exclusive. `0` in penalty/timeout multipliers = disable protection = fail-open.
**Apply:** For any rate limit, penalty, timeout, or threshold field — document explicitly whether 0 is valid. Default: reject 0 in protection multipliers.

---

## Architecture & Design

### H18 — TypeScript + esbuild for intelligence-layer tools; never PowerShell for mathematical computation

**Evidence:** The intelligence layer (decision-audit-engine, risk-calibrator, knowledge-graph-engine, outcome-learning, intelligence-fabric, predictive-intervention) required linear algebra, graph algorithms, statistical scoring, and probabilistic models. Implementing these in PowerShell produced fragile, verbose, hard-to-test code. TypeScript with esbuild produces a self-contained standalone bundle (no `node_modules` at runtime), native array/object algebra, type-safe contracts, and testability with Jest or Vitest.
**Rule:** Any tool that involves matrix operations, graph traversal algorithms, statistical distributions, probabilistic models, or ML-adjacent scoring must be implemented in TypeScript and bundled with esbuild into a `tools/dist/*.js` standalone. PowerShell is the orchestration shell; TypeScript is the computation engine. PowerShell calls the bundle via `node tools/dist/tool-name.js`.
**Apply:** Boundary test: if implementing it in PowerShell requires `[Math]::Round`, nested hashtables, and more than 20 lines of arithmetic — that's the TypeScript boundary. Use `esbuild src/tool.ts --bundle --platform=node --outfile=tools/dist/tool.js`. Never implement graph PageRank, SLO burn-rate algebra, or probabilistic risk scoring in `.ps1`.

---

### H7 — Module-scope Set detects duplicates at load time, not runtime

**Evidence:** A `Set<string>` at module scope guaranteed namespace uniqueness because presets are initialized at load. If presets were lazy-initialized, detection would fail silently.
**Rule:** Module-scope uniqueness detection only works for values initialized at load time. For dynamic values, use an explicit runtime structure.
**Apply:** When adding a new entry to a module-scope registry, verify the value doesn't already exist in the Set. Errors thrown at load are immediately visible.

---

### H8 — Fail-closed default in switch/match is mandatory for entitlement engines

**Evidence:** Entitlement engine had `default: return { allowed: false }` in its switch — any unknown capability was denied. Correct fail-closed posture.
**Rule:** In entitlement, auth, and permission engines, the switch/match default must always be deny. Never allow-by-default for unknown capabilities.
**Apply:** When adding a new capability to an engine, add it explicitly to the switch. Never rely on the default for valid capabilities.

---

### H9 — Parallel wiring to the same boundary is security tech debt

**Evidence:** CREATE_DRAFT had two parallel code paths enforcing the same email-verification rule: one in middleware, one in the entitlement engine. Future divergence is a real risk.
**Rule:** A critical boundary must have a single decision point. Two parallel paths with the same semantics are security tech debt — they will diverge.
**Apply:** When consolidating (e.g. B3-class work), eliminate the duplicate path rather than adding a third. One source of truth per boundary.
