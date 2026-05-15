# Recipe: Prepare a release

## Objective

Run the standard command sequence before tagging, with explicit residual-risk handling.

## When to use

- You own a release cut — pair with [prepare-release playbook narrative](../playbooks/release.md) and [RELEASE-READINESS.md](../docs/RELEASE-READINESS.md).

## Commands

```powershell
pwsh ./tools/os-validate.ps1 -Profile standard -Json
pwsh ./tools/verify-git-hygiene.ps1 -Json
pwsh ./tools/os-validate.ps1 -Profile strict -Json
```

## Expected result

- Standard + strict complete per policy; Git hygiene acceptable for your branch rules; documented residual risk for any waived item.

## Acceptable warnings

- Only those explicitly allowed by your release policy (document the owner).

## Unacceptable warnings/failures

- Hidden drift, undocumented **skip**/**warn**, or missing human sign-off for production promotion — see [production-safety.md](../policies/production-safety.md).

## Next step if it fails

1. Stop the release line; open an incident or fix branch per [incident.md](../playbooks/incident.md) if production is affected.
2. Re-run failed verifier in isolation with `-Json` and attach output to the ticket.
3. Update [CHANGELOG.md](../CHANGELOG.md) and release notes only after gates are honestly green.
