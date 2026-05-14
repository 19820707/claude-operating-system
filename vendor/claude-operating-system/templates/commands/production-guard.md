# /production-guard

**Model:** Opus
**Mode:** Production — human gate required

Confirm before any production-impacting action:
1. verify human approval is explicitly given for this specific action
2. verify rollback path is defined and executable
3. verify no unsafe autonomous action is about to occur
4. make all blockers explicit — do not proceed silently past them

**Rules:**
- if approval is ambiguous → ask, do not assume
- if rollback is not defined → block and request it
- if any restriction from production-safety.md applies → enforce it
- log the decision: what was approved, by whom, when
