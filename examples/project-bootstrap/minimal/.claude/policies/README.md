# Policies under `.claude/policies/`

After `init-project.ps1`, markdown policies are copied from the OS repo:

- `policies/*.md` → `.claude/policies/`
- `templates/critical-surfaces/*.md` → `.claude/policies/` (same destination)

Use these as the binding governance surface for the project. Do not paste API keys or production URLs into policy files.
