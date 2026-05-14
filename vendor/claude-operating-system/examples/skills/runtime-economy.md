# Example: runtime-economy

1. User asks to “validate everything” after a one-file doc edit.
2. Run `pwsh ./tools/os-validate.ps1 -Profile quick -Json` first; only escalate to `standard` if quick fails or risk is high.
