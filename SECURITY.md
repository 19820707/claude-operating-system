# SECURITY

## Scope

Claude OS Runtime manages local files, bootstrap scripts, project `.claude/` artifacts, CI validation, operational policies, and agent-facing workflows.

## Critical surfaces

Changes touching any of the following require explicit review and **human approval required**:

- authentication or authorization policy;
- secrets, tokens, credentials, API keys, or environment variables;
- PII, customer data, private paths, logs, reports, or generated traces;
- filesystem mutation outside declared project/runtime directories;
- CI/CD, deployment, release, package publishing, or permissions;
- rollback behavior, validation gates, or safety checklists.

## Reporting

Do not include secrets, tokens, credentials, customer data, PII, raw stack traces, or private local paths in public issues or pull requests.

When reporting a vulnerability, include:

- affected file or command;
- expected safe behavior;
- observed unsafe behavior;
- minimal reproduction without secrets;
- suggested mitigation, if known.

## Output handling

Runtime tools should summarize failures and use safe redaction for user-facing output. Do not paste raw generated JSON, stack traces, tokens, secrets, or PII into final reports.

## Default posture

Claude OS Runtime is local-first and does not require network access, telemetry, embeddings, external providers, or cloud services for its core operation.
