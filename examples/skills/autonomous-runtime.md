# Example: autonomous-runtime

1. After editing Markdown under `docs/`, run `pwsh ./tools/os-autopilot.ps1 -Goal "validate documentation drift" -Profile quick -DryRun -Json` and confirm `requiresApproval` is false.
2. Escalate profile to `standard` only if quick is inconclusive or the change touched manifests/schemas.
