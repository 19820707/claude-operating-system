# Recipe: Initialize a new project

## Objective

Create a project `.claude` tree (and adapters) from this repository without surprising overwrites.

## When to use

- New repo or folder needs Claude OS scaffolding — overview in [QUICKSTART.md](../docs/QUICKSTART.md); full playbook [bootstrap-project.md](../playbooks/bootstrap-project.md).

## Commands

```powershell
pwsh ./init-project.ps1 -ProjectPath ..\my-project -DryRun -SkipGitInit
pwsh ./init-project.ps1 -ProjectPath ..\my-project -SkipGitInit
```

## Expected result

- Dry-run lists expected files; live run completes with exit code **0** and critical paths present under the target.

## Acceptable warnings

- Tooling may warn about optional Bash on Windows; do not treat as pass for CI that requires Bash — see [VALIDATION.md](../docs/VALIDATION.md).

## Unacceptable warnings/failures

- `init-project` non-zero exit, missing critical paths from `bootstrap-manifest.json`, or overwriting user data without confirmation.

## Next step if it fails

1. Compare output to [bootstrap-manifest.json](../bootstrap-manifest.json) `projectBootstrap.criticalPaths`.
2. Re-run with `-DryRun` after fixing template or manifest issues.
3. For policy on adapters, read [multi-tool-adapters.md](../policies/multi-tool-adapters.md).
