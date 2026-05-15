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

---

## Deployment & Infrastructure

### H11 — docker-vite-env-injection

**Evidence:** VITE_* vars defined only in Railway/CI environment were not embedded in the built assets — Vite requires them at build time, not runtime.
**Rule:** VITE_* variables require `ARG` + `ENV` in the Dockerfile to be embedded by Vite at build time. Defining them only in the platform CI/environment is insufficient.
**Apply:** Pattern: `ARG VITE_X` then `ENV VITE_X=$VITE_X` before `RUN pnpm build`. Every VITE_* var consumed by the app must have a corresponding ARG+ENV pair.

---

### H12 — envsubst-nginx-filter

**Evidence:** `envsubst` without an explicit filter replaced nginx internal variables (`$uri`, `$request_uri`, etc.), corrupting the nginx config and causing 500s.
**Rule:** Always pass an explicit variable filter to `envsubst`. Without it, all shell-style variables in the template are substituted, including nginx's own.
**Apply:** `envsubst '$PORT' < nginx.conf.template > /etc/nginx/conf.d/default.conf` — single quotes are mandatory (passes the literal string `$PORT` to envsubst, not the shell value).

---

### H13 — dockerfile-node-version-match

**Evidence:** Node version in `FROM node:XX` diverged from `engines.node` in `package.json`, causing dependency resolution failures at runtime that did not appear in local dev.
**Rule:** The Node version in `FROM node:XX` must match the `engines.node` field in the root `package.json`. Divergence causes runtime dependency failures.
**Apply:** After any Node upgrade, update both. Add a CI lint step or Dockerfile comment linking to `package.json engines.node`.

---

### H14 — vite-external-dependencies

**Evidence:** UI and i18n dependencies marked as `external` in `rollupOptions.external` were missing from the built bundle, causing runtime crashes in production.
**Rule:** UI libraries and i18n dependencies must never be listed in `rollupOptions.external`. Only native bridges (e.g. `@capacitor/core`) that are guaranteed to exist in the host environment should be external.
**Apply:** Audit `rollupOptions.external` on every Vite config change. Flag any non-native dependency as a defect.
