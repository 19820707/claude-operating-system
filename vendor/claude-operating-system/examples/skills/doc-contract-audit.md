# Example: doc-contract-audit

1. README lists `pwsh ./tools/foo.ps1` but the file was renamed; `verify-doc-contract-consistency` should fail until README is updated.
2. Fix README or restore the script; re-run the verifier.
