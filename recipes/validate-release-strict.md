# Recipe: Validate release (strict)

## Objective

Run **standard** then **strict** validation paths appropriate before a release or production-impacting merge.

## When to use

- Before tagging, production deploy, or when CI mirrors **strict** — see [RELEASE-READINESS.md](../docs/RELEASE-READINESS.md) and playbooks [release.md](../playbooks/release.md).

## Commands

```powershell
pwsh ./tools/os-validate.ps1 -Profile standard -Json
pwsh ./tools/os-validate.ps1 -Profile strict -Json -SkipBashSyntax   # add -RequireBash on CI when required
```

Full aggregate (when bash / git policy satisfied):

```powershell
pwsh ./tools/os-validate-all.ps1 -Strict -Json
```

## Expected result

- **strict** profile completes with no **fail** steps; **warn** only where your policy explicitly allows (often clean Git for strict health).

## Acceptable warnings

- **Git hygiene warn** on non-release local trees only if policy allows; otherwise clean the tree before calling it green — see [GIT-RECOVERY.md](../GIT-RECOVERY.md) if needed.

## Unacceptable warnings/failures

- Skills drift **fail**, playbooks/recipes **Strict** failures, `os-validate-all` **fail**, or treating **warn** as passed for release.

## Next step if it fails

1. Run the suggested command from the tool envelope (often `verify-os-health.ps1` or `verify-git-hygiene.ps1`).
2. For drift: [repair-adapter-drift.md](repair-adapter-drift.md) and [SKILLS.md](../docs/SKILLS.md).
3. Escalate with evidence per [production-safety.md](../policies/production-safety.md).
