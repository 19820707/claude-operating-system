# Skill regression tests (lightweight)

JSON **test cases** under **`cases/`** describe how a **`skillId`** should bind to a **`routeId`** in **`capability-manifest.json`**, and how that pair aligns with **`skills-manifest.json`** — without invoking an LLM.

Run:

```powershell
pwsh ./tools/test-skills.ps1
pwsh ./tools/test-skills.ps1 -Json
```

Schema: **`schemas/skill-test-case.schema.json`**.

When you add a skill to **`relevantSkills`** on a route, add or update a case so CI catches accidental contract drift (validators, forbidden shortcuts, operating mode, approvals).
