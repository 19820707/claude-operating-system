# Scope Control Policy

Claude OS agents must keep reads, writes, validation, and summaries proportional to the task.

## Principle

A repository may contain secrets, generated outputs, private artifacts, dependencies, and unrelated WIP. Agents must not treat every file as available context.

`.claudeignore` defines paths that are out of scope for routine agent discovery, indexing, summaries, and graph/context generation.

## Default exclusions

Project templates should exclude at least:

```gitignore
.env*
*.pem
*.key
*.p12
*.pfx
secrets/
credentials/
node_modules/
vendor/
dist/
build/
coverage/
reports/
.cache/
.local/
graphify-out/cache/
```

## Rules

- **Complexity:** do not add process, automation, or repo surface unless it becomes a **contract** (manifest/schema), **validator** (declared in `script-manifest.json`), **playbook** (`playbooks/` + `playbook-manifest.json`), **skill** (`source/skills/` + `skills-manifest.json`), or another **auditable artifact** (e.g. `quality-gates/*.json`, checklist under `checklists/`) with a clear enforcement or review path. Informal convention alone is not enough.
- Do not read ignored paths during broad discovery.
- Do not include ignored paths in generated context graphs or summaries.
- Do not override `.claudeignore` silently.
- If a task explicitly requires an ignored path, stop and request approval with the exact path and reason.
- `.claudeignore` is not a security boundary; it is an agent scope-control contract.

## Critical surfaces

Even when not ignored, the following require **human approval required** before mutation:

- secrets / credentials;
- auth / payments / production;
- CI/CD / deploy / permissions;
- migrations / live data;
- destructive filesystem changes.

## Reporting

When scope expansion is needed, report:

1. current scoped files;
2. requested additional path;
3. reason;
4. risk;
5. validation benefit.
