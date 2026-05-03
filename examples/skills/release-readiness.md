# Example: release-readiness

1. Before tagging, run `pwsh ./tools/os-validate.ps1 -Profile strict -Json` and capture envelopes.
2. Record residual risk (e.g. known flaky test) and obtain explicit human sign-off on the tag.
